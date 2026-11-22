variable "regiao" {
  description = "Região da AWS (a mesma do ambiente)."
  type        = string
  default     = "us-east-1"

  validation {
    condition     = var.regiao == "us-east-1"
    error_message = "O ambiente vive em us-east-1 (exigência do certificado do CloudFront)."
  }
}

variable "projeto" {
  description = "Nome curto do projeto."
  type        = string
  default     = "prumo"
}

variable "ambiente" {
  description = "Ambiente que o pipeline implanta."
  type        = string
  default     = "producao"
}

variable "repositorio_github" {
  description = "Repositório no formato dono/nome."
  type        = string
  default     = "JhMicucci/Projetos6_Arquitetura"
}

variable "branch" {
  description = "Branch que dispara o pipeline."
  type        = string
  default     = "main"
}

variable "conexao_github_arn" {
  description = "ARN de uma conexão CodeConnections já aprovada. Vazio = cria uma nova."
  type        = string
  default     = ""
}

variable "bucket_state" {
  description = "Bucket do state do Terraform (saída do bootstrap)."
  type        = string
}

variable "zona_dns" {
  description = "Zona pública do Route 53."
  type        = string
  default     = "labdenuvemarquiteturavinicius.click"
}

variable "subdominio" {
  description = "Subdomínio do site."
  type        = string
  default     = "app"
}

variable "cidrs_grafana" {
  description = "IPs (em /32) que podem abrir o Grafana."
  type        = list(string)
}

variable "emails_alerta" {
  description = "Quem recebe o alerta de gasto."
  type        = list(string)
}

variable "orcamento_mensal_usd" {
  description = "Limite mensal do alerta de gasto, em dólares."
  type        = number
  default     = 10
}

variable "variaveis_app" {
  description = "Variáveis do app que não são segredo (RELEASE_*...)."
  type        = map(string)
  default     = {}
}
