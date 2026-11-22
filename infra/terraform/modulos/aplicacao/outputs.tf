output "cluster" {
  description = "Nome do cluster ECS."
  value       = aws_ecs_cluster.principal.name
}

output "servico" {
  description = "Nome do serviço ECS."
  value       = aws_ecs_service.app.name
}

output "definicao_tarefa" {
  description = "ARN da revisão da task definition em uso."
  value       = aws_ecs_task_definition.app.arn
}

output "grupo_logs" {
  description = "Grupo de log dos contêineres."
  value       = aws_cloudwatch_log_group.ecs.name
}
