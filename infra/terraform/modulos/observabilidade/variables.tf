variable "nome" {
  description = "Prefixo dos recursos, ex.: prumo-producao."
  type        = string
}

variable "subrede_id" {
  description = "Sub-rede pública da EC2."
  type        = string
}

variable "cidr_subrede" {
  description = "Bloco da sub-rede pública (para fixar o IP privado no 10º endereço)."
  type        = string
}

variable "grupo_seguranca_id" {
  description = "Security group da observabilidade."
  type        = string
}

variable "chave_kms_arn" {
  description = "Chave KMS do disco e da senha do Grafana."
  type        = string
}

variable "tipo_instancia" {
  description = "Tipo da EC2. O otel-lgtm usa perto de 2 GB de memória."
  type        = string
  default     = "t3.medium"
}

variable "disco_gb" {
  description = "Disco raiz, em GB."
  type        = number
  default     = 30
}

variable "imagem_lgtm" {
  description = "Imagem do grafana/otel-lgtm, com versão fixa."
  type        = string
  default     = "grafana/otel-lgtm:0.40.0"
}

variable "versao_senha" {
  description = "Incremente para gerar uma senha nova do Grafana."
  type        = number
  default     = 1
}
