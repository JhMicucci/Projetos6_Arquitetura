# Alerta de gasto (FinOps): avisa por e-mail quando o mês passa de 80% do
# limite e quando a PREVISÃO do mês passa de 100%. Não desliga nada: é aviso.
# A notificação por e-mail do AWS Budgets não exige confirmação.

resource "aws_budgets_budget" "mensal" {
  name         = "${var.nome}-mensal"
  budget_type  = "COST"
  limit_amount = tostring(var.limite_usd)
  limit_unit   = "USD"
  time_unit    = "MONTHLY"

  notification {
    comparison_operator        = "GREATER_THAN"
    threshold                  = 80
    threshold_type             = "PERCENTAGE"
    notification_type          = "ACTUAL"
    subscriber_email_addresses = var.emails
  }

  notification {
    comparison_operator        = "GREATER_THAN"
    threshold                  = 100
    threshold_type             = "PERCENTAGE"
    notification_type          = "FORECASTED"
    subscriber_email_addresses = var.emails
  }
}
