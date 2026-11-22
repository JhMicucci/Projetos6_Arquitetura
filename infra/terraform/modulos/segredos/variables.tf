variable "nome" {
  description = "Prefixo dos recursos, ex.: prumo-producao."
  type        = string
}

variable "chave_kms_arn" {
  description = "Chave KMS que cifra o segredo."
  type        = string
}

variable "versao_segredos" {
  description = "Incremente para gerar e gravar segredos novos (rotação)."
  type        = number
  default     = 1
}
