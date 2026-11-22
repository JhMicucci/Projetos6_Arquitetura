output "alb_id" {
  description = "Security group do ALB."
  value       = aws_security_group.alb.id
}

output "app_id" {
  description = "Security group das tarefas (app e migrador)."
  value       = aws_security_group.app.id
}

output "banco_id" {
  description = "Security group do Aurora."
  value       = aws_security_group.banco.id
}

output "endpoints_id" {
  description = "Security group dos VPC Endpoints de interface."
  value       = aws_security_group.endpoints.id
}

output "observabilidade_id" {
  description = "Security group da EC2 de observabilidade."
  value       = aws_security_group.observabilidade.id
}
