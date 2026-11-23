# Ambiente de produção do Prumo na AWS: a composição dos módulos.
#
#   Usuários ──> CloudFront + ACM ──> ALB (públicas) ──> ECS Fargate (app) ──> Aurora (dados)
#                                                         │
#                                                         └─OTLP─> EC2 de observabilidade
#
# Esta raiz é aplicada PELO PIPELINE (estágio Deploy), com a tag da imagem do
# commit em `versao_imagem`. O pipeline, o ECR e o bucket de artefatos vivem
# em outra raiz (infra/terraform/cicd), para o pipeline não aplicar a si mesmo.
# Passo a passo: docs/pipeline.md.


provider "aws" {
  region = var.regiao

  default_tags {
    tags = {
      Projeto       = var.projeto
      Ambiente      = var.ambiente
      GerenciadoPor = "terraform"
    }
  }
}

# O repositório de imagens é criado pela raiz do CI/CD; aqui só é lido.
data "aws_ecr_repository" "app" {
  name = var.repositorio_ecr
}

locals {
  nome         = "${var.projeto}-${var.ambiente}"
  prefixo_logs = "/${var.projeto}/${var.ambiente}"
  dominio      = "${var.subdominio}.${var.zona_dns}"

  imagem_app      = "${data.aws_ecr_repository.app.repository_url}:${var.versao_imagem}"
  imagem_migrador = "${data.aws_ecr_repository.app.repository_url}:migrador-${var.versao_imagem}"
}

module "criptografia" {
  source = "../../modulos/criptografia"

  nome         = local.nome
  prefixo_logs = local.prefixo_logs
}

module "rede" {
  source = "../../modulos/rede"

  nome               = local.nome
  prefixo_logs       = local.prefixo_logs
  chave_kms_arn      = module.criptografia.chave_arn
  retencao_logs_dias = var.retencao_logs_dias
}

module "grupos_seguranca" {
  source = "../../modulos/grupos-seguranca"

  nome          = local.nome
  vpc_id        = module.rede.vpc_id
  cidrs_grafana = var.cidrs_grafana
}

# Endpoints de interface numa zona só (a primeira), por FinOps.
module "endpoints" {
  source = "../../modulos/endpoints"

  nome               = local.nome
  vpc_id             = module.rede.vpc_id
  subredes           = [module.rede.subredes_app[0]]
  grupo_seguranca_id = module.grupos_seguranca.endpoints_id
  tabela_privada_id  = module.rede.tabela_privada_id
}

module "banco" {
  source = "../../modulos/banco"

  nome               = local.nome
  subredes           = module.rede.subredes_dados
  grupo_seguranca_id = module.grupos_seguranca.banco_id
  chave_kms_arn      = module.criptografia.chave_arn
  acu_minima         = var.aurora_acu_minima
  acu_maxima         = var.aurora_acu_maxima
}

module "segredos" {
  source = "../../modulos/segredos"

  nome            = local.nome
  chave_kms_arn   = module.criptografia.chave_arn
  versao_segredos = var.versao_segredos
}

module "observabilidade" {
  source = "../../modulos/observabilidade"

  nome               = local.nome
  subrede_id         = module.rede.subredes_publicas[0]
  cidr_subrede       = module.rede.cidrs_publicas[0]
  grupo_seguranca_id = module.grupos_seguranca.observabilidade_id
  chave_kms_arn      = module.criptografia.chave_arn
  tipo_instancia     = var.tipo_instancia_observabilidade
}

module "certificado" {
  source = "../../modulos/certificado"

  zona    = var.zona_dns
  dominio = local.dominio
}

module "balanceador" {
  source = "../../modulos/balanceador"

  nome               = local.nome
  vpc_id             = module.rede.vpc_id
  subredes           = module.rede.subredes_publicas
  grupo_seguranca_id = module.grupos_seguranca.alb_id
}

module "borda" {
  source = "../../modulos/borda"

  dominio                = local.dominio
  certificado_arn        = module.certificado.arn
  dns_origem             = module.balanceador.dns
  valor_cabecalho_origem = module.balanceador.valor_cabecalho_origem
}

module "dns" {
  source = "../../modulos/dns"

  zona_id            = module.certificado.zona_id
  dominio            = local.dominio
  dominio_cloudfront = module.borda.dominio_cloudfront
  zona_cloudfront    = module.borda.zona_cloudfront
}

module "aplicacao" {
  source = "../../modulos/aplicacao"

  nome               = local.nome
  prefixo_logs       = local.prefixo_logs
  chave_kms_arn      = module.criptografia.chave_arn
  subredes           = module.rede.subredes_app
  grupo_seguranca_id = module.grupos_seguranca.app_id
  grupo_alvo_arn     = module.balanceador.grupo_alvo_arn
  imagem_app         = local.imagem_app
  imagem_migrador    = local.imagem_migrador
  segredo_app_arn    = module.segredos.arn
  chaves_segredo_app = module.segredos.chaves
  segredo_banco_arn  = module.banco.segredo_arn
  endpoint_otlp      = module.observabilidade.endpoint_otlp
  variaveis_app      = var.variaveis_app
  quantidade_tarefas = var.quantidade_tarefas
  usar_spot          = var.usar_fargate_spot
  cpu                = var.cpu_tarefa
  memoria            = var.memoria_tarefa
  retencao_logs_dias = var.retencao_logs_dias

  # As tarefas só sobem com o caminho até os serviços da AWS pronto.
  depends_on = [module.endpoints]
}

module "orcamento" {
  source = "../../modulos/orcamento"

  nome       = local.nome
  limite_usd = var.orcamento_mensal_usd
  emails     = var.emails_alerta
}
