# Conexão com o GitHub (AWS CodeConnections).
#
# O Terraform cria a conexão no estado PENDENTE: a AWS exige que alguém com
# acesso ao repositório conclua o aperto de mão no console uma única vez
# (Developer Tools → Settings → Connections → "Update pending connection").
# Até lá, o estágio Fonte do pipeline falha. Ver docs/pipeline.md, passo 4.
#
# Se a organização já tem uma conexão aprovada, passe o ARN em
# `conexao_github_arn` e nada é criado aqui.
#
# Recurso do serviço NOVO (CodeConnections, ARN `arn:aws:codeconnections:`), e
# não o antigo `aws_codestarconnections_connection` (ARN
# `arn:aws:codestar-connections:`). Com o ARN antigo, o push na branch nunca
# disparou o pipeline, em dois ambientes seguidos, embora o *Release change*
# funcionasse; o pipeline de outro projeto da equipe, na mesma conta, com o
# ARN novo, dispara normalmente.

resource "aws_codeconnections_connection" "github" {
  count = var.conexao_github_arn == "" ? 1 : 0

  # Nome diferente do da conexão antiga, que só é destruída depois de esta
  # existir: os dois não convivem com o mesmo nome no meio do apply.
  name          = substr("${var.nome}-conexao-github", 0, 32)
  provider_type = "GitHub"
}

locals {
  conexao_arn = (
    var.conexao_github_arn != ""
    ? var.conexao_github_arn
    : aws_codeconnections_connection.github[0].arn
  )
}
