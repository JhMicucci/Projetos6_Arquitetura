output "arn" {
  description = "ARN do certificado já validado."
  value       = aws_acm_certificate_validation.site.certificate_arn
}

output "zona_id" {
  description = "ID da zona do Route 53."
  value       = data.aws_route53_zone.zona.zone_id
}
