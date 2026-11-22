output "endpoint_otlp" {
  description = "Endereço OTLP HTTP do Collector, pelo IP privado."
  value       = "http://${local.ip_privado}:4318"
}

output "url_grafana" {
  description = "Endereço do Grafana (só abre do IP autorizado)."
  value       = "http://${aws_eip.observabilidade.public_ip}:3000"
}

output "ip_publico" {
  description = "Elastic IP da EC2."
  value       = aws_eip.observabilidade.public_ip
}

output "instancia_id" {
  description = "ID da EC2 (alvo do Session Manager)."
  value       = aws_instance.observabilidade.id
}

output "parametro_senha" {
  description = "Parâmetro do SSM com a senha do admin do Grafana."
  value       = aws_ssm_parameter.senha_grafana.name
}
