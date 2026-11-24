output "endpoint" {
  description = "Endpoint do writer do cluster."
  value       = aws_rds_cluster.principal.endpoint
}

output "segredo_arn" {
  description = "ARN do segredo com as credenciais (vira DATABASE_SECRET_ID nas tarefas)."
  value       = aws_secretsmanager_secret.conexao.arn

  # Quem usa o segredo vai conectar no banco. O cluster fica pronto em segundos,
  # mas sem a instância escritora não há quem atenda na 5432: num apply do
  # zero, o ECS subia em paralelo, o migrador tomava ECONNREFUSED e o circuit
  # breaker derrubava o serviço. Esperar a instância (e o segredo preenchido)
  # põe as tarefas depois do banco de pé.
  depends_on = [
    aws_rds_cluster_instance.escritor,
    aws_secretsmanager_secret_version.conexao,
  ]
}

output "cluster_id" {
  description = "Identificador do cluster."
  value       = aws_rds_cluster.principal.id
}

output "versao_motor" {
  description = "Versão do Aurora PostgreSQL escolhida."
  value       = aws_rds_cluster.principal.engine_version
}
