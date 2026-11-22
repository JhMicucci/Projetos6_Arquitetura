output "nome" {
  description = "Nome do orçamento no AWS Budgets."
  value       = aws_budgets_budget.mensal.name
}
