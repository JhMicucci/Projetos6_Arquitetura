output "endpoint" {
  description = "Endpoint do writer do cluster."
  value       = aws_rds_cluster.principal.endpoint
}

output "segredo_arn" {
  description = "ARN do segredo com as credenciais (vira DATABASE_SECRET_ID nas tarefas)."
  value       = aws_secretsmanager_secret.conexao.arn
}

output "cluster_id" {
  description = "Identificador do cluster."
  value       = aws_rds_cluster.principal.id
}

output "versao_motor" {
  description = "Versão do Aurora PostgreSQL escolhida."
  value       = aws_rds_cluster.principal.engine_version
}
