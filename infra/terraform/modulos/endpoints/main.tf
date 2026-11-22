# VPC Endpoints: o caminho das tarefas até os serviços da AWS sem NAT Gateway.
#
# Interface (pagos, ~US$ 7/mês cada por zona): numa ZONA SÓ, por FinOps. As
# tarefas da outra zona chegam a eles atravessando zona, o que custa centavos
# de tráfego; o preço é que o endpoint vira ponto único de falha (decisão
# registrada em docs/pipeline.md).
#   ecr.api, ecr.dkr     baixar a imagem
#   secretsmanager       segredos do app e credenciais do banco
#   logs                 stdout dos contêineres no CloudWatch
#
# Gateway (gratuito): S3, onde o ECR guarda as camadas das imagens.

data "aws_region" "atual" {}

resource "aws_vpc_endpoint" "interface" {
  for_each = toset(var.servicos_interface)

  vpc_id              = var.vpc_id
  service_name        = "com.amazonaws.${data.aws_region.atual.region}.${each.key}"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = var.subredes
  security_group_ids  = [var.grupo_seguranca_id]
  private_dns_enabled = true

  tags = { Name = "${var.nome}-${each.key}" }
}

resource "aws_vpc_endpoint" "s3" {
  vpc_id            = var.vpc_id
  service_name      = "com.amazonaws.${data.aws_region.atual.region}.s3"
  vpc_endpoint_type = "Gateway"
  route_table_ids   = [var.tabela_privada_id]

  tags = { Name = "${var.nome}-s3" }
}
