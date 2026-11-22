variable "nome" {
  description = "Prefixo dos recursos, ex.: prumo-producao."
  type        = string
}

variable "vpc_id" {
  description = "VPC dos grupos."
  type        = string
}

variable "porta_app" {
  description = "Porta em que o contêiner do app escuta."
  type        = number
  default     = 3000
}

variable "cidrs_grafana" {
  description = "IPs (em /32) que podem abrir o Grafana na porta 3000."
  type        = list(string)

  validation {
    condition     = length(var.cidrs_grafana) > 0 && alltrue([for c in var.cidrs_grafana : c != "0.0.0.0/0"])
    error_message = "O Grafana não fica aberto para a internet: informe o seu IP em /32."
  }
}
