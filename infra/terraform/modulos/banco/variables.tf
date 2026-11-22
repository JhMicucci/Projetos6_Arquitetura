variable "nome" {
  description = "Prefixo dos recursos, ex.: prumo-producao."
  type        = string
}

variable "subredes" {
  description = "Sub-redes de dados (duas zonas, exigência do Aurora)."
  type        = list(string)
}

variable "grupo_seguranca_id" {
  description = "Security group do banco."
  type        = string
}

variable "chave_kms_arn" {
  description = "Chave KMS do armazenamento e do segredo."
  type        = string
}

variable "versao_postgresql" {
  description = "Versão maior do Aurora PostgreSQL; a mais nova dela é escolhida na criação."
  type        = string
  default     = "16"
}

variable "nome_banco" {
  description = "Nome do banco criado no cluster."
  type        = string
  default     = "prumo"
}

variable "usuario_mestre" {
  description = "Usuário mestre do cluster."
  type        = string
  default     = "prumo_admin"
}

variable "versao_senha" {
  description = "Incremente para gerar e gravar uma senha nova (rotação)."
  type        = number
  default     = 1
}

variable "acu_minima" {
  description = "Capacidade mínima em ACU. 0,5 = sempre ligado no menor tamanho."
  type        = number
  default     = 0.5
}

variable "acu_maxima" {
  description = "Capacidade máxima em ACU."
  type        = number
  default     = 2
}
