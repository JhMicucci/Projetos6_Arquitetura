# Os security groups do desenho. Cada regra referencia OUTRO GRUPO (ou uma
# prefix list gerenciada da AWS), nunca um IP solto, com uma exceção
# declarada: o Grafana, que só aceita o IP de quem administra.
#
#   CloudFront ─80─> alb ─3000─> app ─5432─> banco
#                                 │ ─443──> endpoints (ECR, Secrets Manager, Logs)
#                                 │ ─443──> S3 (prefix list do endpoint de gateway)
#                                 └ ─4318─> observabilidade <─3000─ IP do admin
#
# As descrições ficam em ASCII: a API da EC2 recusa acento e apóstrofo nelas.

data "aws_region" "atual" {}

data "aws_ec2_managed_prefix_list" "cloudfront" {
  name = "com.amazonaws.global.cloudfront.origin-facing"
}

data "aws_ec2_managed_prefix_list" "s3" {
  name = "com.amazonaws.${data.aws_region.atual.region}.s3"
}

resource "aws_security_group" "alb" {
  name        = "${var.nome}-alb"
  description = "ALB: aceita apenas o CloudFront na porta 80"
  vpc_id      = var.vpc_id
  tags        = { Name = "${var.nome}-alb" }
}

resource "aws_security_group" "app" {
  name        = "${var.nome}-app"
  description = "Tarefas Fargate: aceitam apenas o ALB na porta 3000"
  vpc_id      = var.vpc_id
  tags        = { Name = "${var.nome}-app" }
}

resource "aws_security_group" "banco" {
  name        = "${var.nome}-banco"
  description = "Aurora: aceita apenas as tarefas na porta 5432"
  vpc_id      = var.vpc_id
  tags        = { Name = "${var.nome}-banco" }
}

resource "aws_security_group" "endpoints" {
  name        = "${var.nome}-endpoints"
  description = "VPC Endpoints de interface: aceitam apenas as tarefas na 443"
  vpc_id      = var.vpc_id
  tags        = { Name = "${var.nome}-endpoints" }
}

resource "aws_security_group" "observabilidade" {
  name        = "${var.nome}-observabilidade"
  description = "EC2 de observabilidade: OTLP das tarefas e Grafana do IP autorizado"
  vpc_id      = var.vpc_id
  tags        = { Name = "${var.nome}-observabilidade" }
}

# ---------------------------------------------------------------------------
# ALB
# ---------------------------------------------------------------------------

resource "aws_vpc_security_group_ingress_rule" "alb_cloudfront" {
  security_group_id = aws_security_group.alb.id
  description       = "HTTP apenas dos servidores de origem do CloudFront"
  ip_protocol       = "tcp"
  from_port         = 80
  to_port           = 80
  prefix_list_id    = data.aws_ec2_managed_prefix_list.cloudfront.id
}

resource "aws_vpc_security_group_egress_rule" "alb_app" {
  security_group_id            = aws_security_group.alb.id
  description                  = "Encaminha para as tarefas"
  ip_protocol                  = "tcp"
  from_port                    = var.porta_app
  to_port                      = var.porta_app
  referenced_security_group_id = aws_security_group.app.id
}

# ---------------------------------------------------------------------------
# Tarefas
# ---------------------------------------------------------------------------

resource "aws_vpc_security_group_ingress_rule" "app_alb" {
  security_group_id            = aws_security_group.app.id
  description                  = "Trafego do ALB, inclusive o health check"
  ip_protocol                  = "tcp"
  from_port                    = var.porta_app
  to_port                      = var.porta_app
  referenced_security_group_id = aws_security_group.alb.id
}

resource "aws_vpc_security_group_egress_rule" "app_endpoints" {
  security_group_id            = aws_security_group.app.id
  description                  = "ECR, Secrets Manager e CloudWatch Logs pelos endpoints"
  ip_protocol                  = "tcp"
  from_port                    = 443
  to_port                      = 443
  referenced_security_group_id = aws_security_group.endpoints.id
}

resource "aws_vpc_security_group_egress_rule" "app_s3" {
  security_group_id = aws_security_group.app.id
  description       = "Camadas das imagens do ECR no S3, pelo endpoint de gateway"
  ip_protocol       = "tcp"
  from_port         = 443
  to_port           = 443
  prefix_list_id    = data.aws_ec2_managed_prefix_list.s3.id
}

resource "aws_vpc_security_group_egress_rule" "app_banco" {
  security_group_id            = aws_security_group.app.id
  description                  = "Aurora PostgreSQL"
  ip_protocol                  = "tcp"
  from_port                    = 5432
  to_port                      = 5432
  referenced_security_group_id = aws_security_group.banco.id
}

resource "aws_vpc_security_group_egress_rule" "app_otlp" {
  security_group_id            = aws_security_group.app.id
  description                  = "Telemetria OTLP HTTP para o Collector"
  ip_protocol                  = "tcp"
  from_port                    = 4318
  to_port                      = 4318
  referenced_security_group_id = aws_security_group.observabilidade.id
}

# ---------------------------------------------------------------------------
# Banco e endpoints: só recebem das tarefas
# ---------------------------------------------------------------------------

resource "aws_vpc_security_group_ingress_rule" "banco_app" {
  security_group_id            = aws_security_group.banco.id
  description                  = "PostgreSQL apenas das tarefas"
  ip_protocol                  = "tcp"
  from_port                    = 5432
  to_port                      = 5432
  referenced_security_group_id = aws_security_group.app.id
}

resource "aws_vpc_security_group_ingress_rule" "endpoints_app" {
  security_group_id            = aws_security_group.endpoints.id
  description                  = "HTTPS apenas das tarefas"
  ip_protocol                  = "tcp"
  from_port                    = 443
  to_port                      = 443
  referenced_security_group_id = aws_security_group.app.id
}

# ---------------------------------------------------------------------------
# Observabilidade
# ---------------------------------------------------------------------------

resource "aws_vpc_security_group_ingress_rule" "observabilidade_otlp" {
  security_group_id            = aws_security_group.observabilidade.id
  description                  = "OTLP HTTP apenas das tarefas"
  ip_protocol                  = "tcp"
  from_port                    = 4318
  to_port                      = 4318
  referenced_security_group_id = aws_security_group.app.id
}

resource "aws_vpc_security_group_ingress_rule" "observabilidade_grafana" {
  for_each = toset(var.cidrs_grafana)

  security_group_id = aws_security_group.observabilidade.id
  description       = "Grafana apenas do IP autorizado"
  ip_protocol       = "tcp"
  from_port         = 3000
  to_port           = 3000
  cidr_ipv4         = each.value
}

# E20 (teste de reprovação): SSH aberto para a internet. O Trivy deve barrar.
resource "aws_vpc_security_group_ingress_rule" "observabilidade_ssh" {
  security_group_id = aws_security_group.observabilidade.id
  description       = "SSH para depurar a EC2"
  ip_protocol       = "tcp"
  from_port         = 22
  to_port           = 22
  cidr_ipv4         = "0.0.0.0/0"
}

# A EC2 fica na sub-rede pública e baixa a imagem do Grafana, os pacotes do
# sistema e fala com o Session Manager pela internet, tudo em 443. O destino é
# aberto porque esses serviços não têm IP fixo; a restrição está na porta.
# trivy:ignore:AWS-0104
resource "aws_vpc_security_group_egress_rule" "observabilidade_https" {
  security_group_id = aws_security_group.observabilidade.id
  description       = "HTTPS para imagens, pacotes e Session Manager"
  ip_protocol       = "tcp"
  from_port         = 443
  to_port           = 443
  cidr_ipv4         = "0.0.0.0/0"
}
