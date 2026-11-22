output "arn" {
  description = "ARN do segredo do app."
  value       = aws_secretsmanager_secret.app.arn
}

output "nome" {
  description = "Nome do segredo do app."
  value       = aws_secretsmanager_secret.app.name
}

output "chaves" {
  description = "Chaves do JSON, que viram variáveis de ambiente das tarefas."
  value       = ["ADMIN_SENHA", "ADMIN_COOKIE_SECRET", "SESSAO_CHAVE"]
}
