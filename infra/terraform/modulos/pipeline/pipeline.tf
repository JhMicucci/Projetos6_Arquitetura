# O pipeline, estágio por estágio:
#
#   Fonte ─> Validacao ─> Imagem ─> Plano ─> Implantacao ─> Fumaca
#            (seguranca ‖ iac ‖ qualidade ‖ observabilidade ‖ jornadas)
#
# Validacao: as fitness functions, em paralelo; qualquer uma reprova e nada
#   é construído.
# Imagem: site e migrador; só vão para o ECR depois do Trivy.
# Plano: terraform plan salvo como artefato, com trava contra destruir dado.
# Implantacao: aplica EXATAMENTE o plano salvo; termina com o ECS estável.
# Fumaca: confere de fora, pela internet, o que está no ar.
#
# Dispara com push na branch configurada. Sem aprovação manual (decisão da
# equipe): o push na `main` vai até a produção.

data "aws_caller_identity" "atual" {}
data "aws_region" "atual" {}

locals {
  conta  = data.aws_caller_identity.atual.account_id
  regiao = data.aws_region.atual.region

  # O CodePipeline resolve isto para o SHA do commit que disparou a execução.
  variaveis_commit = [
    { name = "COMMIT_SHA", value = "#{Fonte.CommitId}", type = "PLAINTEXT" },
  ]

  validacao = ["seguranca", "iac", "qualidade", "observabilidade", "jornadas"]
}

data "aws_iam_policy_document" "confianca_pipeline" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["codepipeline.amazonaws.com"]
    }
    condition {
      test     = "StringEquals"
      variable = "aws:SourceAccount"
      values   = [local.conta]
    }
  }
}

resource "aws_iam_role" "pipeline" {
  name               = "${var.nome}-codepipeline"
  assume_role_policy = data.aws_iam_policy_document.confianca_pipeline.json
}

data "aws_iam_policy_document" "pipeline" {
  statement {
    sid = "Artefatos"
    actions = [
      "s3:GetObject",
      "s3:GetObjectVersion",
      "s3:GetBucketVersioning",
      "s3:PutObject",
      "s3:PutObjectAcl",
    ]
    resources = [aws_s3_bucket.artefatos.arn, "${aws_s3_bucket.artefatos.arn}/*"]
  }

  statement {
    sid       = "ChaveDoCiCd"
    actions   = ["kms:Decrypt", "kms:Encrypt", "kms:GenerateDataKey*", "kms:DescribeKey"]
    resources = [var.chave_kms_arn]
  }

  statement {
    sid       = "ConexaoGitHub"
    actions   = ["codestar-connections:UseConnection", "codeconnections:UseConnection"]
    resources = [local.conexao_arn]
  }

  statement {
    sid       = "CodeBuild"
    actions   = ["codebuild:StartBuild", "codebuild:BatchGetBuilds"]
    resources = [for projeto in aws_codebuild_project.etapa : projeto.arn]
  }
}

resource "aws_iam_role_policy" "pipeline" {
  name   = "pipeline"
  role   = aws_iam_role.pipeline.id
  policy = data.aws_iam_policy_document.pipeline.json
}

resource "aws_codepipeline" "principal" {
  name           = var.nome
  role_arn       = aws_iam_role.pipeline.arn
  pipeline_type  = "V2"
  execution_mode = "QUEUED"

  artifact_store {
    type     = "S3"
    location = aws_s3_bucket.artefatos.bucket

    encryption_key {
      type = "KMS"
      id   = var.chave_kms_arn
    }
  }

  # A regra, declarada: push na branch configurada inicia o pipeline.
  # Conferir o que vale na AWS: aws codepipeline get-pipeline --query pipeline.triggers
  trigger {
    provider_type = "CodeStarSourceConnection"

    git_configuration {
      source_action_name = "GitHub"

      push {
        branches {
          includes = [var.branch]
        }
      }
    }
  }

  stage {
    name = "Fonte"

    action {
      name             = "GitHub"
      category         = "Source"
      owner            = "AWS"
      provider         = "CodeStarSourceConnection"
      version          = "1"
      namespace        = "Fonte"
      output_artifacts = ["fonte"]

      configuration = {
        ConnectionArn        = local.conexao_arn
        FullRepositoryId     = var.repositorio_github
        BranchName           = var.branch # usado no início manual (Release change)
        OutputArtifactFormat = "CODEBUILD_CLONE_REF"
        # Sem DetectChanges: igual ao pipeline da mesma conta que dispara com
        # push. Quem filtra a branch é o bloco `trigger` acima.
      }
    }
  }

  stage {
    name = "Validacao"

    dynamic "action" {
      for_each = local.validacao
      content {
        name            = title(action.value)
        category        = "Test"
        owner           = "AWS"
        provider        = "CodeBuild"
        version         = "1"
        run_order       = 1
        input_artifacts = ["fonte"]

        configuration = {
          ProjectName          = aws_codebuild_project.etapa[action.value].name
          EnvironmentVariables = jsonencode(local.variaveis_commit)
        }
      }
    }
  }

  stage {
    name = "Imagem"

    action {
      name            = "SiteEMigrador"
      category        = "Build"
      owner           = "AWS"
      provider        = "CodeBuild"
      version         = "1"
      input_artifacts = ["fonte"]

      configuration = {
        ProjectName          = aws_codebuild_project.etapa["imagem"].name
        EnvironmentVariables = jsonencode(local.variaveis_commit)
      }
    }
  }

  stage {
    name = "Plano"

    action {
      name             = "TerraformPlan"
      category         = "Build"
      owner            = "AWS"
      provider         = "CodeBuild"
      version          = "1"
      namespace        = "Plano"
      input_artifacts  = ["fonte"]
      output_artifacts = ["plano"]

      configuration = {
        ProjectName          = aws_codebuild_project.etapa["plano"].name
        EnvironmentVariables = jsonencode(local.variaveis_commit)
      }
    }
  }

  stage {
    name = "Implantacao"

    action {
      name            = "TerraformApply"
      category        = "Build"
      owner           = "AWS"
      provider        = "CodeBuild"
      version         = "1"
      namespace       = "Implantacao"
      input_artifacts = ["fonte", "plano"]

      configuration = {
        ProjectName          = aws_codebuild_project.etapa["implantacao"].name
        PrimarySource        = "fonte"
        EnvironmentVariables = jsonencode(local.variaveis_commit)
      }
    }
  }

  stage {
    name = "Fumaca"

    action {
      name            = "ConferirProducao"
      category        = "Test"
      owner           = "AWS"
      provider        = "CodeBuild"
      version         = "1"
      input_artifacts = ["fonte"]

      configuration = {
        ProjectName = aws_codebuild_project.etapa["fumaca"].name
        # O que a implantação descobriu (endereços) chega aqui pelo namespace.
        EnvironmentVariables = jsonencode(concat(local.variaveis_commit, [
          { name = "URL_SITE", value = "#{Implantacao.URL_SITE}", type = "PLAINTEXT" },
          { name = "DNS_ALB", value = "#{Implantacao.DNS_ALB}", type = "PLAINTEXT" },
          { name = "IP_OBSERVABILIDADE", value = "#{Implantacao.IP_OBSERVABILIDADE}", type = "PLAINTEXT" },
        ]))
      }
    }
  }
}
