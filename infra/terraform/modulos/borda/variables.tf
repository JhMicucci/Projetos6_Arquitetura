variable "dominio" {
  description = "Endereço do site, ex.: app.labdenuvemarquiteturavinicius.click."
  type        = string
}

variable "certificado_arn" {
  description = "Certificado do ACM (em us-east-1) para o domínio."
  type        = string
}

variable "dns_origem" {
  description = "Nome DNS do ALB."
  type        = string
}

variable "valor_cabecalho_origem" {
  description = "Valor do cabeçalho X-Origem-Verificada."
  type        = string
  sensitive   = true
}

variable "classe_de_preco" {
  description = "Classe de preço do CloudFront. PriceClass_All inclui os pontos de presença da América do Sul (perto de Recife); na escala do projeto, o nível gratuito cobre qualquer classe."
  type        = string
  default     = "PriceClass_All"
}
