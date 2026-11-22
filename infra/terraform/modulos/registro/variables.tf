variable "nome" {
  description = "Nome do repositório ECR."
  type        = string
}

variable "chave_kms_arn" {
  description = "Chave KMS que cifra as imagens. Nulo = AES-256 gerenciado pela AWS."
  type        = string
  default     = null
}

variable "imagens_guardadas" {
  description = "Quantas imagens ficam no repositório (cada commit gera duas: site e migrador)."
  type        = number
  default     = 20
}

variable "apagar_com_imagens" {
  description = "Permite que o terraform destroy apague o repositório mesmo com imagens dentro."
  type        = bool
  default     = true
}
