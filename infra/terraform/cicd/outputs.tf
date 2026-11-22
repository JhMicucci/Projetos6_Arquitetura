output "pipeline" {
  description = "Nome do pipeline no CodePipeline."
  value       = module.pipeline.nome
}

output "conexao_github_status" {
  description = "Se PENDING, aprove a conexão no console antes do primeiro push (docs/pipeline.md)."
  value       = module.pipeline.conexao_github_status
}

output "conexao_github_arn" {
  description = "ARN da conexão com o GitHub."
  value       = module.pipeline.conexao_github_arn
}

output "repositorio_ecr" {
  description = "Repositório das imagens."
  value       = module.registro.url
}

output "comando_ultima_execucao" {
  description = "Mostra a última execução e o tipo de disparo (WebhookV2 = veio de um push)."
  value       = "aws codepipeline list-pipeline-executions --region ${var.regiao} --pipeline-name ${module.pipeline.nome} --max-items 1 --query \"pipelineExecutionSummaries[0].[status,trigger.triggerType,sourceRevisions[0].revisionId]\" --output text"
}
