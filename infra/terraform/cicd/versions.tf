terraform {
  required_version = ">= 1.11"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
  }

  # Mesmo bucket do ambiente, chave separada. Os papéis do pipeline só
  # alcançam prumo/producao/*: este state fica fora do alcance deles.
  backend "s3" {
    key          = "prumo/cicd/terraform.tfstate"
    encrypt      = true
    use_lockfile = true
  }
}
