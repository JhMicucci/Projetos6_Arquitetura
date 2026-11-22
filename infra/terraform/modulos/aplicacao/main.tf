# O Prumo no ECS Fargate.
#
# Cada tarefa tem dois contêineres, na ordem:
#   1. `migrador` (não essencial): aplica as migrações e, com o banco vazio,
#      carrega a base sintética. Pega um lock consultivo no Postgres, então as
#      tarefas que sobem juntas se revezam (scripts/db.ts). Termina e sai.
#   2. `app` (essencial): só sobe se o migrador terminar com SUCESSO.
# Assim toda tarefa nova (deploy, troca de Spot, recuperação) garante o schema
# antes de servir, sem um passo a mais no pipeline.
#
# Capacidade: 1 tarefa sob demanda sempre, e o restante em Fargate Spot (uns
# 70% mais barato, pode ser interrompido com 2 minutos de aviso).

data "aws_caller_identity" "atual" {}
data "aws_region" "atual" {}

locals {
  conta  = data.aws_caller_identity.atual.account_id
  regiao = data.aws_region.atual.region

  log = {
    logDriver = "awslogs"
    options = {
      awslogs-group         = aws_cloudwatch_log_group.ecs.name
      awslogs-region        = local.regiao
      awslogs-stream-prefix = "prumo"
    }
  }

  # O que app e migrador têm em comum: como chegar no banco.
  ambiente_banco = [
    { name = "DATABASE_SECRET_ID", value = var.segredo_banco_arn },
    { name = "DATABASE_SSL", value = "exigir" },
    { name = "DATABASE_SSL_CA", value = "/app/certificados/rds-global-bundle.pem" },
    { name = "AWS_REGION", value = local.regiao },
  ]

  # Telemetria: ver src/lib/telemetria/ e o .env.example.
  ambiente_otel = [
    { name = "OTEL_EXPORTER_OTLP_ENDPOINT", value = var.endpoint_otlp },
    { name = "OTEL_EXPORTER_OTLP_PROTOCOL", value = "http/protobuf" },
    { name = "OTEL_SERVICE_NAME", value = "prumo" },
    { name = "OTEL_METRICS_EXPORTER", value = "otlp" },
    { name = "OTEL_LOGS_EXPORTER", value = "otlp" },
    { name = "OTEL_SEMCONV_STABILITY_OPT_IN", value = "http" },
    { name = "OTEL_NODE_RESOURCE_DETECTORS", value = "env,host,serviceinstance" },
  ]

  segredos_app = [
    for chave in var.chaves_segredo_app : {
      name      = chave
      valueFrom = "${var.segredo_app_arn}:${chave}::"
    }
  ]

  ambiente_extra = [for nome, valor in var.variaveis_app : { name = nome, value = valor }]

  estrategia = var.usar_spot ? [
    { provedor = "FARGATE", base = 1, peso = 0 },
    { provedor = "FARGATE_SPOT", base = 0, peso = 1 },
    ] : [
    { provedor = "FARGATE", base = 0, peso = 1 },
  ]
}

resource "aws_cloudwatch_log_group" "ecs" {
  name              = "${var.prefixo_logs}/ecs"
  retention_in_days = var.retencao_logs_dias
  kms_key_id        = var.chave_kms_arn
}

# Container Insights desligado: o detalhe por tarefa já vem da telemetria do
# app, e o Insights cobra por métrica.
resource "aws_ecs_cluster" "principal" {
  name = var.nome

  setting {
    name  = "containerInsights"
    value = "disabled"
  }
}

resource "aws_ecs_cluster_capacity_providers" "principal" {
  cluster_name       = aws_ecs_cluster.principal.name
  capacity_providers = ["FARGATE", "FARGATE_SPOT"]

  dynamic "default_capacity_provider_strategy" {
    for_each = local.estrategia
    content {
      capacity_provider = default_capacity_provider_strategy.value.provedor
      base              = default_capacity_provider_strategy.value.base
      weight            = default_capacity_provider_strategy.value.peso
    }
  }
}

# ---------------------------------------------------------------------------
# Papéis: o de EXECUÇÃO é do agente do ECS (baixar imagem, entregar segredos,
# escrever log); o da TAREFA é do código do app em execução.
# ---------------------------------------------------------------------------

data "aws_iam_policy_document" "confianca_tarefas" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["ecs-tasks.amazonaws.com"]
    }
    condition {
      test     = "StringEquals"
      variable = "aws:SourceAccount"
      values   = [local.conta]
    }
  }
}

resource "aws_iam_role" "execucao" {
  name               = "${var.nome}-ecs-execucao"
  assume_role_policy = data.aws_iam_policy_document.confianca_tarefas.json
}

resource "aws_iam_role_policy_attachment" "execucao_padrao" {
  role       = aws_iam_role.execucao.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

data "aws_iam_policy_document" "execucao_segredos" {
  statement {
    sid       = "SegredosEntreguesComoVariavel"
    actions   = ["secretsmanager:GetSecretValue"]
    resources = [var.segredo_app_arn]
  }
  statement {
    sid       = "DecifrarSegredos"
    actions   = ["kms:Decrypt"]
    resources = [var.chave_kms_arn]
  }
}

resource "aws_iam_role_policy" "execucao_segredos" {
  name   = "segredos-do-app"
  role   = aws_iam_role.execucao.id
  policy = data.aws_iam_policy_document.execucao_segredos.json
}

resource "aws_iam_role" "tarefa" {
  name               = "${var.nome}-ecs-tarefa"
  assume_role_policy = data.aws_iam_policy_document.confianca_tarefas.json
}

# O app (e o migrador) leem as credenciais do banco por conta própria, pelo
# SDK, a partir de DATABASE_SECRET_ID. Só este segredo, e mais nada.
data "aws_iam_policy_document" "tarefa" {
  statement {
    sid       = "CredenciaisDoBanco"
    actions   = ["secretsmanager:GetSecretValue"]
    resources = [var.segredo_banco_arn]
  }
  statement {
    sid       = "DecifrarCredenciais"
    actions   = ["kms:Decrypt"]
    resources = [var.chave_kms_arn]
  }
}

resource "aws_iam_role_policy" "tarefa" {
  name   = "credenciais-do-banco"
  role   = aws_iam_role.tarefa.id
  policy = data.aws_iam_policy_document.tarefa.json
}

# ---------------------------------------------------------------------------
# Task definition
# ---------------------------------------------------------------------------

resource "aws_ecs_task_definition" "app" {
  family                   = "${var.nome}-app"
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = var.cpu
  memory                   = var.memoria
  execution_role_arn       = aws_iam_role.execucao.arn
  task_role_arn            = aws_iam_role.tarefa.arn

  runtime_platform {
    operating_system_family = "LINUX"
    cpu_architecture        = "X86_64"
  }

  # O sistema de arquivos é somente leitura; o Fargate não tem tmpfs, então os
  # dois diretórios que o Next escreve são volumes efêmeros da tarefa.
  volume {
    name = "tmp"
  }
  volume {
    name = "cache-next"
  }

  container_definitions = jsonencode([
    {
      name                   = "migrador"
      image                  = var.imagem_migrador
      essential              = false
      readonlyRootFilesystem = true
      environment            = local.ambiente_banco
      logConfiguration       = local.log
    },
    {
      name                   = "app"
      image                  = var.imagem_app
      essential              = true
      readonlyRootFilesystem = true
      portMappings           = [{ containerPort = var.porta_app, protocol = "tcp" }]
      dependsOn              = [{ containerName = "migrador", condition = "SUCCESS" }]
      environment            = concat(local.ambiente_banco, local.ambiente_otel, local.ambiente_extra)
      secrets                = local.segredos_app
      mountPoints = [
        { sourceVolume = "tmp", containerPath = "/tmp", readOnly = false },
        { sourceVolume = "cache-next", containerPath = "/app/.next/cache", readOnly = false },
      ]
      # A imagem é distroless: sem curl nem shell, o próprio Node checa.
      healthCheck = {
        command     = ["CMD", "/nodejs/bin/node", "-e", "fetch('http://127.0.0.1:${var.porta_app}/api/saude').then(r=>process.exit(r.ok?0:1)).catch(()=>process.exit(1))"]
        interval    = 15
        timeout     = 5
        retries     = 3
        startPeriod = 30
      }
      stopTimeout      = 30
      logConfiguration = local.log
    },
  ])
}

resource "aws_ecs_service" "app" {
  name            = "${var.nome}-app"
  cluster         = aws_ecs_cluster.principal.id
  task_definition = aws_ecs_task_definition.app.arn
  desired_count   = var.quantidade_tarefas

  dynamic "capacity_provider_strategy" {
    for_each = local.estrategia
    content {
      capacity_provider = capacity_provider_strategy.value.provedor
      base              = capacity_provider_strategy.value.base
      weight            = capacity_provider_strategy.value.peso
    }
  }

  network_configuration {
    subnets          = var.subredes
    security_groups  = [var.grupo_seguranca_id]
    assign_public_ip = false
  }

  load_balancer {
    target_group_arn = var.grupo_alvo_arn
    container_name   = "app"
    container_port   = var.porta_app
  }

  health_check_grace_period_seconds  = 60
  deployment_minimum_healthy_percent = 100
  deployment_maximum_percent         = 200

  # Revisão nova que não fica saudável volta sozinha para a anterior.
  deployment_circuit_breaker {
    enable   = true
    rollback = true
  }

  propagate_tags = "SERVICE"

  # O `terraform apply` do pipeline só termina com o serviço estável: um
  # deploy quebrado reprova o estágio, em vez de parecer verde.
  wait_for_steady_state = true

  depends_on = [aws_ecs_cluster_capacity_providers.principal]
}
