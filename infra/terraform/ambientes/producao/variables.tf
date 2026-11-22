variable "regiao" {
  description = "Região da AWS. Fica em us-east-1: o CloudFront só aceita certificado do ACM dessa região."
  type        = string
  default     = "us-east-1"

  validation {
    condition     = var.regiao == "us-east-1"
    error_message = "O certificado do CloudFront precisa estar em us-east-1."
  }
}

variable "projeto" {
  description = "Nome curto do projeto, usado em todos os nomes."
  type        = string
  default     = "prumo"
}

variable "ambiente" {
  description = "Nome do ambiente."
  type        = string
  default     = "producao"
}

variable "zona_dns" {
  description = "Zona pública do Route 53 onde mora o domínio."
  type        = string
  default     = "labdenuvemarquiteturavinicius.click"
}

variable "subdominio" {
  description = "Subdomínio do site dentro da zona."
  type        = string
  default     = "app"
}

variable "repositorio_ecr" {
  description = "Nome do repositório ECR criado pela raiz do CI/CD."
  type        = string
  default     = "prumo-producao"
}

variable "versao_imagem" {
  description = "Tag da imagem a implantar: o SHA do commit. O pipeline preenche."
  type        = string

  validation {
    condition     = can(regex("^[0-9a-f]{7,40}$", var.versao_imagem))
    error_message = "A tag da imagem é o SHA do commit (hexadecimal)."
  }
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

variable "quantidade_tarefas" {
  description = "Tarefas do app no ar."
  type        = number
  default     = 2
}

variable "usar_fargate_spot" {
  description = "1 tarefa sob demanda e o restante em Fargate Spot."
  type        = bool
  default     = true
}

variable "cpu_tarefa" {
  description = "CPU de cada tarefa (256 = 0,25 vCPU)."
  type        = number
  default     = 256
}

variable "memoria_tarefa" {
  description = "Memória de cada tarefa, em MiB."
  type        = number
  default     = 1024
}

variable "aurora_acu_minima" {
  description = "Capacidade mínima do Aurora (0,5 = sempre ligado no menor tamanho)."
  type        = number
  default     = 0.5
}

variable "aurora_acu_maxima" {
  description = "Capacidade máxima do Aurora."
  type        = number
  default     = 2
}

variable "tipo_instancia_observabilidade" {
  description = "Tipo da EC2 de observabilidade."
  type        = string
  default     = "t3.medium"
}

variable "variaveis_app" {
  description = "Variáveis do app que não são segredo (RELEASE_*...)."
  type        = map(string)
  default     = {}
}

variable "versao_segredos" {
  description = "Incremente para girar os segredos do app."
  type        = number
  default     = 1
}

variable "retencao_logs_dias" {
  description = "Retenção dos logs no CloudWatch."
  type        = number
  default     = 30
}
