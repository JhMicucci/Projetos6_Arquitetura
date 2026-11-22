output "url_site" {
  description = "Endereço público do site."
  value       = "https://${local.dominio}"
}

output "url_grafana" {
  description = "Grafana (só abre do IP autorizado)."
  value       = module.observabilidade.url_grafana
}

output "cluster_ecs" {
  description = "Cluster ECS."
  value       = module.aplicacao.cluster
}

output "servico_ecs" {
  description = "Serviço ECS do app."
  value       = module.aplicacao.servico
}

output "imagem_em_uso" {
  description = "Imagem do app implantada."
  value       = local.imagem_app
}

output "versao_aurora" {
  description = "Versão do Aurora PostgreSQL."
  value       = module.banco.versao_motor
}

output "comando_senha_grafana" {
  description = "Lê a senha do admin do Grafana."
  value       = "aws ssm get-parameter --region ${var.regiao} --with-decryption --name ${module.observabilidade.parametro_senha} --query Parameter.Value --output text"
}

output "comando_senha_painel" {
  description = "Lê a senha do painel administrativo do site."
  value       = "aws secretsmanager get-secret-value --region ${var.regiao} --secret-id ${module.segredos.nome} --query SecretString --output text"
}

output "comando_sessao_observabilidade" {
  description = "Terminal na EC2 de observabilidade, sem SSH."
  value       = "aws ssm start-session --region ${var.regiao} --target ${module.observabilidade.instancia_id}"
}
