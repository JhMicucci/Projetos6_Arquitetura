variable "nome" {
  description = "Prefixo dos recursos, ex.: prumo-producao."
  type        = string
}

variable "vpc_id" {
  description = "VPC dos endpoints."
  type        = string
}

variable "subredes" {
  description = "Sub-redes onde ficam os endpoints de interface. Uma só = uma zona (mais barato)."
  type        = list(string)
}

variable "grupo_seguranca_id" {
  description = "Security group dos endpoints de interface."
  type        = string
}

variable "tabela_privada_id" {
  description = "Tabela de rotas que recebe a rota do endpoint de S3."
  type        = string
}

variable "servicos_interface" {
  description = "Serviços com endpoint de interface."
  type        = list(string)
  default     = ["ecr.api", "ecr.dkr", "secretsmanager", "logs"]
}
