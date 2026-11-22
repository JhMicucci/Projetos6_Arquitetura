# A raiz do CI/CD: o que precisa existir ANTES do primeiro deploy e que o
# pipeline não deve aplicar sobre si mesmo.
#
#   chave KMS do CI/CD ─┬─> bucket de artefatos, logs e projetos do CodeBuild
#   ECR (prumo-producao)┘   (as imagens são construídas antes do Plano)
#   CodePipeline + CodeBuild + conexão com o GitHub
#
# Aplicada uma vez, à mão (docs/pipeline.md). A partir daí, cada push na
# `main` faz o pipeline aplicar a raiz do ambiente (ambientes/producao).
#
# Os nomes daqui começam com `prumo-cicd`, e não `prumo-producao`, DE
# PROPÓSITO: o papel de implantação só gerencia IAM com o prefixo do
# ambiente, e assim não alcança os papéis do próprio pipeline.

provider "aws" {
  region = var.regiao

  default_tags {
    tags = {
      Projeto       = var.projeto
      Ambiente      = "cicd"
      GerenciadoPor = "terraform"
    }
  }
}

locals {
  nome         = "${var.projeto}-cicd"
  ambiente     = "${var.projeto}-${var.ambiente}"
  prefixo_logs = "/${var.projeto}/cicd"
  url_site     = "https://${var.subdominio}.${var.zona_dns}"
}

module "criptografia" {
  source = "../modulos/criptografia"

  nome         = local.nome
  prefixo_logs = local.prefixo_logs
}

# O nome do repositório é o do ambiente: é ele que a raiz do ambiente lê.
module "registro" {
  source = "../modulos/registro"

  nome               = local.ambiente
  apagar_com_imagens = true # o destroy termina sem passo manual
}

module "pipeline" {
  source = "../modulos/pipeline"

  nome                      = local.nome
  prefixo_recursos_ambiente = local.ambiente
  prefixo_logs              = local.prefixo_logs
  chave_kms_arn             = module.criptografia.chave_arn
  repositorio_github        = var.repositorio_github
  branch                    = var.branch
  conexao_github_arn        = var.conexao_github_arn
  repositorio_ecr_url       = module.registro.url
  repositorio_ecr_arn       = module.registro.arn
  bucket_state              = var.bucket_state
  url_site                  = local.url_site
  url_repositorio           = "https://github.com/${var.repositorio_github}"

  # O equivalente do terraform.tfvars do ambiente, entregue ao plano e à
  # implantação como TF_VAR_*. Nenhum é segredo.
  variaveis_terraform = {
    cidrs_grafana        = jsonencode(var.cidrs_grafana)
    emails_alerta        = jsonencode(var.emails_alerta)
    orcamento_mensal_usd = tostring(var.orcamento_mensal_usd)
    variaveis_app        = jsonencode(var.variaveis_app)
  }
}
