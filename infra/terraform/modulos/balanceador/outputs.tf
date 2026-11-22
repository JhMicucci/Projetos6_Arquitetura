output "dns" {
  description = "Nome DNS do ALB (origem do CloudFront)."
  value       = aws_lb.principal.dns_name
}

output "grupo_alvo_arn" {
  description = "Target group das tarefas."
  value       = aws_lb_target_group.app.arn
}

output "valor_cabecalho_origem" {
  description = "Valor do cabeçalho X-Origem-Verificada, que só o CloudFront envia."
  value       = random_password.cabecalho_origem.result
  sensitive   = true
}

output "sufixo_arn" {
  description = "Sufixo do ARN do ALB, usado nas métricas do CloudWatch."
  value       = aws_lb.principal.arn_suffix
}
