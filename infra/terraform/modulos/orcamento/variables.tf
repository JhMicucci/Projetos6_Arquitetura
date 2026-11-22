variable "nome" {
  description = "Prefixo dos recursos, ex.: prumo-producao."
  type        = string
}

variable "limite_usd" {
  description = "Limite mensal, em dólares."
  type        = number
}

variable "emails" {
  description = "Quem recebe o aviso."
  type        = list(string)
}
