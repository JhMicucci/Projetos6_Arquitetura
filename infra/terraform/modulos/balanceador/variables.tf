variable "nome" {
  description = "Prefixo dos recursos (até 28 caracteres, pelo limite de nome do ALB)."
  type        = string

  validation {
    condition     = length(var.nome) <= 28
    error_message = "O nome do target group (nome + \"-app\") passa de 32 caracteres."
  }
}

variable "vpc_id" {
  description = "VPC do target group."
  type        = string
}

variable "subredes" {
  description = "Sub-redes públicas, uma por zona."
  type        = list(string)
}

variable "grupo_seguranca_id" {
  description = "Security group do ALB."
  type        = string
}

variable "porta_app" {
  description = "Porta do contêiner do app."
  type        = number
  default     = 3000
}
