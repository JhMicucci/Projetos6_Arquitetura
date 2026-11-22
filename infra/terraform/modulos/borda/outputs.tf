output "dominio_cloudfront" {
  description = "Endereço *.cloudfront.net da distribuição."
  value       = aws_cloudfront_distribution.site.domain_name
}

output "zona_cloudfront" {
  description = "Zona hospedada do CloudFront, alvo dos registros alias."
  value       = aws_cloudfront_distribution.site.hosted_zone_id
}

output "id" {
  description = "ID da distribuição."
  value       = aws_cloudfront_distribution.site.id
}
