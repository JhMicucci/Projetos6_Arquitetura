output "vpc_id" {
  description = "ID da VPC."
  value       = aws_vpc.principal.id
}

output "zonas" {
  description = "As duas zonas de disponibilidade usadas, em ordem."
  value       = local.zonas
}

output "subredes_publicas" {
  description = "Sub-redes públicas, na ordem das zonas."
  value       = [for zona in local.zonas : aws_subnet.publica[zona].id]
}

output "cidrs_publicas" {
  description = "Blocos das sub-redes públicas, na ordem das zonas."
  value       = [for zona in local.zonas : aws_subnet.publica[zona].cidr_block]
}

output "subredes_app" {
  description = "Sub-redes privadas das tarefas, na ordem das zonas."
  value       = [for zona in local.zonas : aws_subnet.app[zona].id]
}

output "subredes_dados" {
  description = "Sub-redes privadas do banco, na ordem das zonas."
  value       = [for zona in local.zonas : aws_subnet.dados[zona].id]
}

output "tabela_privada_id" {
  description = "Tabela de rotas das sub-redes privadas (recebe a rota do endpoint de S3)."
  value       = aws_route_table.privada.id
}
