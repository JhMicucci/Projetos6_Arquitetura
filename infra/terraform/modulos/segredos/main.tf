# Segredos do app num único segredo do Secrets Manager (JSON com uma chave por
# variável). Um segredo só custa US$ 0,40/mês em vez de três, e o ECS entrega
# cada chave como variável de ambiente (`valueFrom` com `:CHAVE::`).
#
# Secrets Manager e não SSM Parameter Store, de propósito: as tarefas estão em
# sub-rede privada sem NAT, e o endpoint do Secrets Manager já existe por causa
# do banco. O SSM exigiria mais um endpoint, que custa mais que o segredo.
#
# Valores gerados por recurso EFÊMERO e gravados por atributo WRITE-ONLY: não
# ficam no state. Para girar, incremente `versao_segredos` e aplique.

ephemeral "random_password" "admin_senha" {
  length  = 24
  special = false
}

ephemeral "random_password" "cookie" {
  length  = 64
  special = false
}

# 32 caracteres que, em base64, decodificam em exatamente 32 bytes: o formato
# que src/lib/auth/cripto.ts exige da SESSAO_CHAVE.
ephemeral "random_password" "sessao" {
  length  = 32
  special = false
}

resource "aws_secretsmanager_secret" "app" {
  name                    = "${var.nome}/app"
  description             = "Segredos do Prumo: senha do painel, assinatura do cookie e chave da sessao"
  kms_key_id              = var.chave_kms_arn
  recovery_window_in_days = 0
}

resource "aws_secretsmanager_secret_version" "app" {
  secret_id = aws_secretsmanager_secret.app.id
  secret_string_wo = jsonencode({
    ADMIN_SENHA         = ephemeral.random_password.admin_senha.result
    ADMIN_COOKIE_SECRET = ephemeral.random_password.cookie.result
    SESSAO_CHAVE        = base64encode(ephemeral.random_password.sessao.result)
  })
  secret_string_wo_version = var.versao_segredos
}
