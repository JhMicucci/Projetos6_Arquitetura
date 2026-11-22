variable "nome" {
  description = "Prefixo dos recursos, ex.: prumo-producao."
  type        = string
}

variable "prefixo_logs" {
  description = "Prefixo dos grupos de log, ex.: /prumo/producao."
  type        = string
}

variable "chave_kms_arn" {
  description = "Chave KMS que cifra os flow logs."
  type        = string
}

variable "cidr_vpc" {
  description = "Bloco de endereços da VPC."
  type        = string
  default     = "10.0.0.0/16"
}

variable "retencao_logs_dias" {
  description = "Por quantos dias os flow logs ficam guardados."
  type        = number
  default     = 30
}
