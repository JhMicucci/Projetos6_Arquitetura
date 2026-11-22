variable "zona_id" {
  description = "ID da zona do Route 53."
  type        = string
}

variable "dominio" {
  description = "Endereço do site."
  type        = string
}

variable "dominio_cloudfront" {
  description = "Endereço *.cloudfront.net da distribuição."
  type        = string
}

variable "zona_cloudfront" {
  description = "Zona hospedada do CloudFront."
  type        = string
}
