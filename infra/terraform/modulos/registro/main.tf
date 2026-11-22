# Repositório de imagens do app (site e migrador, tags `<sha>` e
# `migrador-<sha>`). Tag IMUTÁVEL: o SHA do commit aponta sempre para a mesma
# imagem, e é ela que a task definition referencia. Uma imagem que chegou aqui
# já passou pelo Trivy no CodeBuild; o scan do ECR é a segunda opinião,
# contínua, sobre CVEs publicados depois do push.
#
# Cifra: com `chave_kms_arn`, a chave do cliente; sem ela, AES-256 gerenciado
# pela AWS. O ambiente usa AES-256 de propósito: com uma chave de outra raiz
# Terraform, quem puxa a imagem (as tarefas) dependeria de permissão nela.

# trivy:ignore:AWS-0033
resource "aws_ecr_repository" "app" {
  name                 = var.nome
  image_tag_mutability = "IMMUTABLE"
  force_delete         = var.apagar_com_imagens

  image_scanning_configuration {
    scan_on_push = true
  }

  encryption_configuration {
    encryption_type = var.chave_kms_arn == null ? "AES256" : "KMS"
    kms_key         = var.chave_kms_arn
  }
}

resource "aws_ecr_lifecycle_policy" "app" {
  repository = aws_ecr_repository.app.name

  policy = jsonencode({
    rules = [
      {
        rulePriority = 1
        description  = "Camadas sem tag somem em um dia"
        selection = {
          tagStatus   = "untagged"
          countType   = "sinceImagePushed"
          countUnit   = "days"
          countNumber = 1
        }
        action = { type = "expire" }
      },
      {
        rulePriority = 2
        description  = "Guarda as ultimas imagens para rollback"
        selection = {
          tagStatus   = "any"
          countType   = "imageCountMoreThan"
          countNumber = var.imagens_guardadas
        }
        action = { type = "expire" }
      },
    ]
  })
}
