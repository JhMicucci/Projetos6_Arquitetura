# Os projetos do CodeBuild. O que cada um faz está no buildspec versionado em
# infra/codebuild/: o Terraform só diz ONDE roda, com que máquina e com que
# permissão. Mudar um passo do pipeline é um commit, não um terraform apply.

locals {
  # Variáveis do Terraform do ambiente (o que, localmente, fica no
  # terraform.tfvars): chegam ao plano e à implantação como TF_VAR_*.
  ambiente_terraform = merge(
    {
      TF_STATE_BUCKET  = var.bucket_state
      TF_STATE_REGIAO  = local.regiao
      TF_IN_AUTOMATION = "true"
      TF_INPUT         = "0"
    },
    { for nome, valor in var.variaveis_terraform : "TF_VAR_${nome}" => valor },
  )

  projetos = {
    seguranca = {
      descricao    = "Validacao: Gitleaks, Trivy (dependencias, segredos, licencas) e Hadolint"
      computacao   = "BUILD_GENERAL1_SMALL"
      privilegiado = false
      minutos      = 20
      papel        = aws_iam_role.verificacao.arn
      variaveis    = {}
    }
    iac = {
      descricao    = "Validacao: terraform fmt e validate, TFLint e Trivy config"
      computacao   = "BUILD_GENERAL1_SMALL"
      privilegiado = false
      minutos      = 20
      papel        = aws_iam_role.verificacao.arn
      variaveis    = {}
    }
    qualidade = {
      descricao    = "Validacao: lint, tipos, testes com Postgres, build, vazamento e dossie"
      computacao   = "BUILD_GENERAL1_MEDIUM"
      privilegiado = true # sobe o Postgres dos testes num contêiner
      minutos      = 30
      papel        = aws_iam_role.verificacao.arn
      variaveis    = {}
    }
    observabilidade = {
      descricao    = "Validacao: fitness function de observabilidade (span do INSERT sem dado digitado)"
      computacao   = "BUILD_GENERAL1_SMALL"
      privilegiado = true
      minutos      = 20
      papel        = aws_iam_role.verificacao.arn
      variaveis    = {}
    }
    jornadas = {
      descricao    = "Validacao: jornadas criticas no Playwright contra o build de producao"
      computacao   = "BUILD_GENERAL1_MEDIUM"
      privilegiado = true
      minutos      = 40
      papel        = aws_iam_role.verificacao.arn
      variaveis    = {}
    }
    imagem = {
      descricao    = "Imagens do site e do migrador, Trivy nas duas, SBOM e push no ECR"
      computacao   = "BUILD_GENERAL1_MEDIUM"
      privilegiado = true # docker build
      minutos      = 40
      papel        = aws_iam_role.imagem.arn
      variaveis = {
        REPOSITORIO_ECR      = var.repositorio_ecr_url
        NEXT_PUBLIC_SITE_URL = var.url_site
        NEXT_PUBLIC_REPO_URL = var.url_repositorio
      }
    }
    plano = {
      descricao    = "terraform plan do ambiente, com trava contra destruir dado"
      computacao   = "BUILD_GENERAL1_SMALL"
      privilegiado = false
      minutos      = 30
      papel        = aws_iam_role.plano.arn
      variaveis    = local.ambiente_terraform
    }
    implantacao = {
      descricao    = "terraform apply do plano salvo; termina com o ECS estavel"
      computacao   = "BUILD_GENERAL1_SMALL"
      privilegiado = false
      minutos      = 90 # a primeira criação espera Aurora, CloudFront e ACM
      papel        = aws_iam_role.implantacao.arn
      variaveis    = local.ambiente_terraform
    }
    fumaca = {
      descricao    = "Pos-deploy: versao no ar, TLS, cabecalhos e portas fechadas, de fora"
      computacao   = "BUILD_GENERAL1_SMALL"
      privilegiado = false
      minutos      = 20
      papel        = aws_iam_role.verificacao.arn
      variaveis    = {}
    }
  }
}

resource "aws_cloudwatch_log_group" "codebuild" {
  name              = "${var.prefixo_logs}/codebuild"
  retention_in_days = var.retencao_logs_dias
  kms_key_id        = var.chave_kms_arn
}

resource "aws_codebuild_project" "etapa" {
  for_each = local.projetos

  name           = "${var.nome}-${each.key}"
  description    = each.value.descricao
  service_role   = each.value.papel
  build_timeout  = each.value.minutos
  encryption_key = var.chave_kms_arn

  artifacts {
    type = "CODEPIPELINE"
  }

  source {
    type      = "CODEPIPELINE"
    buildspec = "infra/codebuild/${each.key}.yml"
  }

  environment {
    type                        = "LINUX_CONTAINER"
    compute_type                = each.value.computacao
    image                       = var.imagem_codebuild
    image_pull_credentials_type = "CODEBUILD"
    privileged_mode             = each.value.privilegiado

    dynamic "environment_variable" {
      for_each = each.value.variaveis
      content {
        name  = environment_variable.key
        value = environment_variable.value
      }
    }
  }

  cache {
    type  = "LOCAL"
    modes = ["LOCAL_DOCKER_LAYER_CACHE", "LOCAL_CUSTOM_CACHE"]
  }

  logs_config {
    cloudwatch_logs {
      group_name  = aws_cloudwatch_log_group.codebuild.name
      stream_name = each.key
    }
  }
}

# ---------------------------------------------------------------------------
# Papéis, do menor para o maior poder
# ---------------------------------------------------------------------------

data "aws_iam_policy_document" "confianca_codebuild" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["codebuild.amazonaws.com"]
    }
    condition {
      test     = "StringEquals"
      variable = "aws:SourceAccount"
      values   = [local.conta]
    }
  }
}

# O que todo projeto precisa: log, artefatos, a chave do CI/CD, clonar o
# repositório e publicar relatórios JUnit.
data "aws_iam_policy_document" "base" {
  statement {
    sid       = "Logs"
    actions   = ["logs:CreateLogStream", "logs:PutLogEvents"]
    resources = ["${aws_cloudwatch_log_group.codebuild.arn}:*"]
  }

  statement {
    sid       = "ArtefatosDoPipeline"
    actions   = ["s3:GetObject", "s3:GetObjectVersion", "s3:PutObject"]
    resources = ["${aws_s3_bucket.artefatos.arn}/*"]
  }

  statement {
    sid       = "BucketDeArtefatos"
    actions   = ["s3:GetBucketAcl", "s3:GetBucketLocation"]
    resources = [aws_s3_bucket.artefatos.arn]
  }

  statement {
    sid       = "ChaveDoCiCd"
    actions   = ["kms:Decrypt", "kms:Encrypt", "kms:GenerateDataKey*", "kms:DescribeKey"]
    resources = [var.chave_kms_arn]
  }

  # A fonte é uma referência de clone (CODEBUILD_CLONE_REF): o CodeBuild clona
  # o repositório com histórico, para o Gitleaks varrer tudo.
  statement {
    sid = "CloneDoRepositorio"
    actions = [
      "codestar-connections:UseConnection",
      "codestar-connections:GetConnectionToken",
      "codeconnections:UseConnection",
      "codeconnections:GetConnectionToken",
      "codeconnections:GetConnection",
    ]
    resources = [local.conexao_arn]
  }

  statement {
    sid = "Relatorios"
    actions = [
      "codebuild:CreateReportGroup",
      "codebuild:CreateReport",
      "codebuild:UpdateReport",
      "codebuild:BatchPutTestCases",
      "codebuild:BatchPutCodeCoverages",
    ]
    resources = ["arn:aws:codebuild:${local.regiao}:${local.conta}:report-group/${var.nome}-*"]
  }
}

# O state do ambiente, para o plano e a implantação.
data "aws_iam_policy_document" "state" {
  statement {
    sid       = "ListarState"
    actions   = ["s3:ListBucket"]
    resources = ["arn:aws:s3:::${var.bucket_state}"]
  }
  statement {
    sid       = "LerEGravarState"
    actions   = ["s3:GetObject", "s3:PutObject", "s3:DeleteObject"]
    resources = ["arn:aws:s3:::${var.bucket_state}/${var.prefixo_state}/*"]
  }
}

resource "aws_iam_role" "verificacao" {
  name               = "${var.nome}-codebuild-verificacao"
  assume_role_policy = data.aws_iam_policy_document.confianca_codebuild.json
}

resource "aws_iam_role_policy" "verificacao" {
  name   = "verificacao"
  role   = aws_iam_role.verificacao.id
  policy = data.aws_iam_policy_document.base.json
}

# --- Imagem: publica no ECR -------------------------------------------------

data "aws_iam_policy_document" "imagem" {
  source_policy_documents = [data.aws_iam_policy_document.base.json]

  statement {
    sid       = "LoginNoEcr"
    actions   = ["ecr:GetAuthorizationToken"]
    resources = ["*"]
  }

  # Push da imagem nova e pull da que já existe: um Release change roda o
  # mesmo commit, e o imagem.sh baixa a imagem publicada para passar o Trivy
  # de novo. Sem GetDownloadUrlForLayer esse caminho falhava (visto no E24).
  statement {
    sid = "PushEPullDaImagem"
    actions = [
      "ecr:BatchCheckLayerAvailability",
      "ecr:BatchGetImage",
      "ecr:CompleteLayerUpload",
      "ecr:DescribeImages",
      "ecr:GetDownloadUrlForLayer",
      "ecr:InitiateLayerUpload",
      "ecr:PutImage",
      "ecr:UploadLayerPart",
    ]
    resources = [var.repositorio_ecr_arn]
  }
}

resource "aws_iam_role" "imagem" {
  name               = "${var.nome}-codebuild-imagem"
  assume_role_policy = data.aws_iam_policy_document.confianca_codebuild.json
}

resource "aws_iam_role_policy" "imagem" {
  name   = "imagem"
  role   = aws_iam_role.imagem.id
  policy = data.aws_iam_policy_document.imagem.json
}

# --- Plano: só leitura na conta, mais o state -------------------------------

data "aws_iam_policy_document" "plano" {
  source_policy_documents = [data.aws_iam_policy_document.base.json, data.aws_iam_policy_document.state.json]

  # O refresh dos segredos e dos parâmetros lê a versão atual deles.
  statement {
    sid       = "LerSegredosDoAmbiente"
    actions   = ["secretsmanager:GetSecretValue"]
    resources = ["arn:aws:secretsmanager:${local.regiao}:${local.conta}:secret:${var.prefixo_recursos_ambiente}/*"]
  }
  statement {
    sid       = "LerParametrosDoAmbiente"
    actions   = ["ssm:GetParameter", "ssm:GetParameters"]
    resources = ["arn:aws:ssm:${local.regiao}:${local.conta}:parameter/${replace(var.prefixo_recursos_ambiente, "-", "/")}/*"]
  }
  statement {
    sid       = "DecifrarPelosServicos"
    actions   = ["kms:Decrypt"]
    resources = ["*"]
    condition {
      test     = "StringEquals"
      variable = "kms:ViaService"
      values = [
        "secretsmanager.${local.regiao}.amazonaws.com",
        "ssm.${local.regiao}.amazonaws.com",
        "s3.${local.regiao}.amazonaws.com",
      ]
    }
  }
}

resource "aws_iam_role" "plano" {
  name               = "${var.nome}-codebuild-plano"
  assume_role_policy = data.aws_iam_policy_document.confianca_codebuild.json
}

resource "aws_iam_role_policy_attachment" "plano_leitura" {
  role       = aws_iam_role.plano.name
  policy_arn = "arn:aws:iam::aws:policy/ReadOnlyAccess"
}

resource "aws_iam_role_policy" "plano" {
  name   = "plano"
  role   = aws_iam_role.plano.id
  policy = data.aws_iam_policy_document.plano.json
}

# --- Implantação: cria a infraestrutura -------------------------------------
#
# PowerUserAccess dá tudo menos IAM; o IAM vem à parte e só para papéis,
# políticas e perfis de instância com o prefixo do ambiente. Quem assume é só
# o CodeBuild desta conta, e ele só roda o que está na `main` do repositório.

data "aws_iam_policy_document" "implantacao" {
  source_policy_documents = [data.aws_iam_policy_document.base.json, data.aws_iam_policy_document.state.json]

  statement {
    sid     = "IamDoAmbiente"
    actions = ["iam:*"]
    resources = [
      "arn:aws:iam::${local.conta}:role/${var.prefixo_recursos_ambiente}-*",
      "arn:aws:iam::${local.conta}:policy/${var.prefixo_recursos_ambiente}-*",
      "arn:aws:iam::${local.conta}:instance-profile/${var.prefixo_recursos_ambiente}-*",
    ]
  }

  statement {
    sid       = "LerIam"
    actions   = ["iam:Get*", "iam:List*"]
    resources = ["*"]
  }

  # ECS, RDS, ELB e o Spot criam o próprio papel vinculado na primeira vez.
  statement {
    sid       = "PapeisVinculadosAosServicos"
    actions   = ["iam:CreateServiceLinkedRole"]
    resources = ["arn:aws:iam::${local.conta}:role/aws-service-role/*"]
  }
}

resource "aws_iam_role" "implantacao" {
  name               = "${var.nome}-codebuild-implantacao"
  assume_role_policy = data.aws_iam_policy_document.confianca_codebuild.json
}

resource "aws_iam_role_policy_attachment" "implantacao_poder" {
  role       = aws_iam_role.implantacao.name
  policy_arn = "arn:aws:iam::aws:policy/PowerUserAccess"
}

resource "aws_iam_role_policy" "implantacao" {
  name   = "implantacao"
  role   = aws_iam_role.implantacao.id
  policy = data.aws_iam_policy_document.implantacao.json
}
