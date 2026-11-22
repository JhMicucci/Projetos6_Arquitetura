# TFLint: a fitness function de estilo e de erro de AWS no Terraform, no
# estágio IaC do pipeline (infra/codebuild/iac.sh). Complementa o Trivy, que
# olha segurança: o TFLint pega tipo de instância inexistente, variável sem
# tipo, recurso declarado e nunca usado.

config {
  # Avalia os módulos locais chamados pelas raízes, com os valores reais.
  call_module_type = "local"
}

plugin "terraform" {
  enabled = true
  preset  = "recommended"
}

plugin "aws" {
  enabled = true
  version = "0.50.0"
  source  = "github.com/terraform-linters/tflint-ruleset-aws"
}
