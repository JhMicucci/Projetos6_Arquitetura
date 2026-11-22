variable "nome" {
  description = "Prefixo dos recursos, ex.: prumo-producao."
  type        = string
}

variable "prefixo_logs" {
  description = "Prefixo dos grupos de log, ex.: /prumo/producao."
  type        = string
}

variable "chave_kms_arn" {
  description = "Chave KMS dos logs e dos segredos."
  type        = string
}

variable "subredes" {
  description = "Sub-redes privadas das tarefas, uma por zona."
  type        = list(string)
}

variable "grupo_seguranca_id" {
  description = "Security group das tarefas."
  type        = string
}

variable "grupo_alvo_arn" {
  description = "Target group do ALB."
  type        = string
}

variable "imagem_app" {
  description = "Imagem do site no ECR, com tag (o SHA do commit)."
  type        = string
}

variable "imagem_migrador" {
  description = "Imagem do migrador no ECR, com tag (migrador-<SHA do commit>)."
  type        = string
}

variable "segredo_app_arn" {
  description = "Segredo com ADMIN_SENHA, ADMIN_COOKIE_SECRET e SESSAO_CHAVE."
  type        = string
}

variable "chaves_segredo_app" {
  description = "Chaves do segredo do app que viram variáveis de ambiente."
  type        = list(string)
}

variable "segredo_banco_arn" {
  description = "Segredo com as credenciais do Aurora (DATABASE_SECRET_ID)."
  type        = string
}

variable "endpoint_otlp" {
  description = "Endereço OTLP HTTP do Collector, ex.: http://10.0.1.10:4318."
  type        = string
}

variable "variaveis_app" {
  description = "Variáveis do app que não são segredo (RELEASE_*...)."
  type        = map(string)
  default     = {}
}

variable "porta_app" {
  description = "Porta do contêiner do app."
  type        = number
  default     = 3000
}

variable "cpu" {
  description = "CPU da tarefa, em unidades (256 = 0,25 vCPU)."
  type        = number
  default     = 256
}

variable "memoria" {
  description = "Memória da tarefa, em MiB."
  type        = number
  default     = 1024
}

variable "quantidade_tarefas" {
  description = "Quantas tarefas o serviço mantém no ar."
  type        = number
  default     = 2
}

variable "usar_spot" {
  description = "1 tarefa sob demanda e o restante em Fargate Spot."
  type        = bool
  default     = true
}

variable "retencao_logs_dias" {
  description = "Retenção dos logs dos contêineres."
  type        = number
  default     = 30
}
