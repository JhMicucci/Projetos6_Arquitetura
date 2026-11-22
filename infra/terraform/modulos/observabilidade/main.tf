# Observabilidade numa EC2 pública só (desenho da Aula 12): a imagem
# grafana/otel-lgtm traz Collector OTLP, Prometheus, Tempo, Loki e Grafana
# num contêiner.
#
#   tarefas ──OTLP 4318──> Collector       (só o security group das tarefas)
#   admin   ──HTTP 3000──> Grafana         (só o IP /32 autorizado)
#
# - IP privado FIXO (o 10º da sub-rede): é o endereço que as tarefas usam no
#   OTEL_EXPORTER_OTLP_ENDPOINT, e ele não muda se a máquina for recriada.
# - Sem chave SSH e sem porta 22: terminal pelo Session Manager.
# - Senha do Grafana aleatória num SecureString do SSM (gratuito; a EC2 tem
#   saída para a internet, então não precisa de endpoint), gravada por
#   atributo write-only: não fica no state.

data "aws_region" "atual" {}
data "aws_caller_identity" "atual" {}

data "aws_ssm_parameter" "ami_al2023" {
  name = "/aws/service/ami-amazon-linux-latest/al2023-ami-kernel-default-x86_64"
}

locals {
  regiao       = data.aws_region.atual.region
  ip_privado   = cidrhost(var.cidr_subrede, 10)
  nome_senha   = "/${replace(var.nome, "-", "/")}/grafana/senha-admin"
  arn_da_senha = "arn:aws:ssm:${local.regiao}:${data.aws_caller_identity.atual.account_id}:parameter${local.nome_senha}"
}

ephemeral "random_password" "grafana" {
  length  = 24
  special = false
}

resource "aws_ssm_parameter" "senha_grafana" {
  name             = local.nome_senha
  description      = "Senha do usuario admin do Grafana"
  type             = "SecureString"
  key_id           = var.chave_kms_arn
  value_wo         = ephemeral.random_password.grafana.result
  value_wo_version = var.versao_senha
}

data "aws_iam_policy_document" "confianca_ec2" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "observabilidade" {
  name               = "${var.nome}-observabilidade"
  assume_role_policy = data.aws_iam_policy_document.confianca_ec2.json
}

resource "aws_iam_role_policy_attachment" "ssm" {
  role       = aws_iam_role.observabilidade.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

data "aws_iam_policy_document" "senha" {
  statement {
    actions   = ["ssm:GetParameter"]
    resources = [local.arn_da_senha]
  }
  statement {
    actions   = ["kms:Decrypt"]
    resources = [var.chave_kms_arn]
  }
}

resource "aws_iam_role_policy" "senha" {
  name   = "senha-do-grafana"
  role   = aws_iam_role.observabilidade.id
  policy = data.aws_iam_policy_document.senha.json
}

resource "aws_iam_instance_profile" "observabilidade" {
  name = "${var.nome}-observabilidade"
  role = aws_iam_role.observabilidade.name
}

# O IP automático existe só para o boot alcançar a internet antes de o
# Elastic IP ser associado; depois o EIP assume.
resource "aws_instance" "observabilidade" {
  ami                         = data.aws_ssm_parameter.ami_al2023.value
  instance_type               = var.tipo_instancia
  subnet_id                   = var.subrede_id
  private_ip                  = local.ip_privado
  vpc_security_group_ids      = [var.grupo_seguranca_id]
  iam_instance_profile        = aws_iam_instance_profile.observabilidade.name
  associate_public_ip_address = true

  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required"
    http_put_response_hop_limit = 1
  }

  root_block_device {
    volume_type           = "gp3"
    volume_size           = var.disco_gb
    encrypted             = true
    kms_key_id            = var.chave_kms_arn
    delete_on_termination = true
  }

  user_data = templatefile("${path.module}/inicializacao.sh.tftpl", {
    regiao          = local.regiao
    parametro_senha = local.nome_senha
    imagem          = var.imagem_lgtm
  })
  user_data_replace_on_change = true

  tags = { Name = "${var.nome}-observabilidade" }

  lifecycle {
    ignore_changes = [ami]
  }

  depends_on = [aws_ssm_parameter.senha_grafana]
}

resource "aws_eip" "observabilidade" {
  domain   = "vpc"
  instance = aws_instance.observabilidade.id
  tags     = { Name = "${var.nome}-observabilidade" }
}
