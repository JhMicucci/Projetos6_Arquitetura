output "ids_interface" {
  description = "IDs dos endpoints de interface, por serviço."
  value       = { for servico, endpoint in aws_vpc_endpoint.interface : servico => endpoint.id }
}

output "s3_id" {
  description = "ID do endpoint de gateway do S3."
  value       = aws_vpc_endpoint.s3.id
}
