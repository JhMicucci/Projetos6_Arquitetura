# Rede do ambiente: a VPC do desenho, em duas zonas de disponibilidade.
#
#                 zona A            zona B
#   pública      10.0.1.0/24       10.0.2.0/24     ALB e a EC2 de observabilidade
#   app          10.0.11.0/24      10.0.12.0/24    tarefas Fargate (sem IP público)
#   dados        10.0.21.0/24      10.0.22.0/24    Aurora
#
# SEM NAT GATEWAY, por FinOps: as sub-redes privadas não têm rota para a
# internet. As tarefas falam com ECR, Secrets Manager e CloudWatch pelos VPC
# Endpoints (módulo `endpoints`) e com o S3 pelo endpoint de gateway, gratuito.

data "aws_availability_zones" "disponiveis" {
  state = "available"
}

locals {
  zonas = slice(data.aws_availability_zones.disponiveis.names, 0, 2)

  # cidrsubnet(10.0.0.0/16, 8, n) = 10.0.n.0/24
  publicas = { for i, zona in local.zonas : zona => cidrsubnet(var.cidr_vpc, 8, 1 + i) }
  app      = { for i, zona in local.zonas : zona => cidrsubnet(var.cidr_vpc, 8, 11 + i) }
  dados    = { for i, zona in local.zonas : zona => cidrsubnet(var.cidr_vpc, 8, 21 + i) }
}

resource "aws_vpc" "principal" {
  cidr_block           = var.cidr_vpc
  enable_dns_support   = true
  enable_dns_hostnames = true # exigido pelo DNS privado dos VPC Endpoints

  tags = { Name = var.nome }
}

# O security group padrão nasce aberto entre seus membros. Zerado, nenhum
# recurso cai nele por engano com acesso que ninguém pediu.
resource "aws_default_security_group" "fechado" {
  vpc_id = aws_vpc.principal.id
  tags   = { Name = "${var.nome}-padrao-fechado" }
}

resource "aws_internet_gateway" "principal" {
  vpc_id = aws_vpc.principal.id
  tags   = { Name = var.nome }
}

resource "aws_subnet" "publica" {
  for_each = local.publicas

  vpc_id            = aws_vpc.principal.id
  availability_zone = each.key
  cidr_block        = each.value

  # Quem precisa de IP público recebe um Elastic IP; a sub-rede não distribui.
  map_public_ip_on_launch = false

  tags = { Name = "${var.nome}-publica-${each.key}", Camada = "publica" }
}

resource "aws_subnet" "app" {
  for_each = local.app

  vpc_id            = aws_vpc.principal.id
  availability_zone = each.key
  cidr_block        = each.value

  tags = { Name = "${var.nome}-app-${each.key}", Camada = "app" }
}

resource "aws_subnet" "dados" {
  for_each = local.dados

  vpc_id            = aws_vpc.principal.id
  availability_zone = each.key
  cidr_block        = each.value

  tags = { Name = "${var.nome}-dados-${each.key}", Camada = "dados" }
}

resource "aws_route_table" "publica" {
  vpc_id = aws_vpc.principal.id
  tags   = { Name = "${var.nome}-publica" }
}

resource "aws_route" "publica_internet" {
  route_table_id         = aws_route_table.publica.id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.principal.id
}

resource "aws_route_table_association" "publica" {
  for_each = aws_subnet.publica

  subnet_id      = each.value.id
  route_table_id = aws_route_table.publica.id
}

# Privada: só a rota local da VPC (e a do S3, que o módulo `endpoints` põe).
resource "aws_route_table" "privada" {
  vpc_id = aws_vpc.principal.id
  tags   = { Name = "${var.nome}-privada" }
}

resource "aws_route_table_association" "app" {
  for_each = aws_subnet.app

  subnet_id      = each.value.id
  route_table_id = aws_route_table.privada.id
}

resource "aws_route_table_association" "dados" {
  for_each = aws_subnet.dados

  subnet_id      = each.value.id
  route_table_id = aws_route_table.privada.id
}

# ---------------------------------------------------------------------------
# Flow logs só do que foi RECUSADO: é a evidência de que as portas fechadas
# estão fechadas, pelo menor volume (e custo) de log possível.
# ---------------------------------------------------------------------------

resource "aws_cloudwatch_log_group" "fluxo" {
  name              = "${var.prefixo_logs}/vpc-recusas"
  retention_in_days = var.retencao_logs_dias
  kms_key_id        = var.chave_kms_arn
}

data "aws_iam_policy_document" "fluxo_confianca" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["vpc-flow-logs.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "fluxo" {
  name               = "${var.nome}-vpc-fluxo"
  assume_role_policy = data.aws_iam_policy_document.fluxo_confianca.json
}

data "aws_iam_policy_document" "fluxo_escrita" {
  statement {
    actions   = ["logs:CreateLogStream", "logs:PutLogEvents", "logs:DescribeLogStreams"]
    resources = ["${aws_cloudwatch_log_group.fluxo.arn}:*"]
  }
}

resource "aws_iam_role_policy" "fluxo" {
  name   = "escrita-flow-logs"
  role   = aws_iam_role.fluxo.id
  policy = data.aws_iam_policy_document.fluxo_escrita.json
}

resource "aws_flow_log" "principal" {
  vpc_id                   = aws_vpc.principal.id
  traffic_type             = "REJECT"
  log_destination_type     = "cloud-watch-logs"
  log_destination          = aws_cloudwatch_log_group.fluxo.arn
  iam_role_arn             = aws_iam_role.fluxo.arn
  max_aggregation_interval = 600
}
