output "fqdn" {
  description = "Nome que os registros resolvem."
  value       = aws_route53_record.site["A"].fqdn
}
