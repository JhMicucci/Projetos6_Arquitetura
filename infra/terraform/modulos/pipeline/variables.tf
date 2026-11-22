variable "nome" {
  description = "Prefixo dos recursos do CI/CD, ex.: prumo-cicd. Não pode começar como o do ambiente."
  type        = string
}

variable "prefixo_recursos_ambiente" {
  description = "Prefixo dos recursos que o pipeline gerencia, ex.: prumo-producao."
  type        = string
}

variable "prefixo_logs" {
  description = "Prefixo dos grupos de log, ex.: /prumo/cicd."
  type        = string
}

variable "chave_kms_arn" {
  description = "Chave KMS do CI/CD (artefatos, logs, projetos do CodeBuild)."
  type        = string
}

variable "repositorio_github" {
  description = "Repositório no formato dono/nome."
  type        = string
}

variable "branch" {
  description = "Branch que dispara o pipeline."
  type        = string
  default     = "main"
}

variable "conexao_github_arn" {
  description = "ARN de uma conexão CodeConnections já aprovada. Vazio = o módulo cria uma (pendente até a aprovação no console)."
  type        = string
  default     = ""
}

variable "repositorio_ecr_url" {
  description = "URL do repositório ECR."
  type        = string
}

variable "repositorio_ecr_arn" {
  description = "ARN do repositório ECR."
  type        = string
}

variable "bucket_state" {
  description = "Bucket do state do Terraform (saída do bootstrap)."
  type        = string
}

variable "prefixo_state" {
  description = "Prefixo das chaves de state do ambiente dentro do bucket."
  type        = string
  default     = "prumo/producao"
}

variable "variaveis_terraform" {
  description = "Variáveis do ambiente (o equivalente do terraform.tfvars) entregues como TF_VAR_*."
  type        = map(string)
  default     = {}
}

variable "url_site" {
  description = "URL pública do site (vira NEXT_PUBLIC_SITE_URL no build)."
  type        = string
}

variable "url_repositorio" {
  description = "URL do repositório (vira NEXT_PUBLIC_REPO_URL no build)."
  type        = string
  default     = ""
}

variable "imagem_codebuild" {
  description = "Imagem gerenciada do CodeBuild (Ubuntu 24.04, com Node 22 e Docker)."
  type        = string
  default     = "aws/codebuild/standard:8.0"
}

variable "retencao_logs_dias" {
  description = "Por quantos dias os logs do CodeBuild ficam guardados."
  type        = number
  default     = 30
}

variable "retencao_artefatos_dias" {
  description = "Por quantos dias os artefatos do pipeline ficam no bucket."
  type        = number
  default     = 30
}

variable "apagar_bucket_com_conteudo" {
  description = "Permite que o terraform destroy apague o bucket de artefatos com conteúdo."
  type        = bool
  default     = true
}
