# Aurora Serverless v2 PostgreSQL, nas sub-redes de dados.
#
# - Sempre ligado (mínimo de 0,5 ACU): decisão da equipe, para não haver a
#   espera de ~15 s da retomada de uma pausa. Máximo baixo, por FinOps.
# - Um writer, sem réplica leitora: o volume do Aurora já guarda 6 cópias em
#   3 zonas; a réplica pagaria um segundo writer parado.
# - A senha do usuário mestre nasce de recurso EFÊMERO e entra por atributo
#   WRITE-ONLY: vai para o Aurora e para o Secrets Manager e não fica no state.
# - O segredo segue o formato que o app lê em DATABASE_SECRET_ID
#   (src/lib/dados/postgres/conexao.ts): username, password, host, port, dbname.

data "aws_rds_engine_version" "postgresql" {
  engine  = "aurora-postgresql"
  version = var.versao_postgresql
  latest  = true
}

resource "aws_db_subnet_group" "dados" {
  name       = var.nome
  subnet_ids = var.subredes
  tags       = { Name = var.nome }
}

ephemeral "random_password" "mestre" {
  length  = 32
  special = false
}

resource "aws_rds_cluster" "principal" {
  cluster_identifier = var.nome
  engine             = "aurora-postgresql"
  engine_mode        = "provisioned"
  engine_version     = data.aws_rds_engine_version.postgresql.version_actual

  database_name              = var.nome_banco
  master_username            = var.usuario_mestre
  master_password_wo         = ephemeral.random_password.mestre.result
  master_password_wo_version = var.versao_senha

  db_subnet_group_name   = aws_db_subnet_group.dados.name
  vpc_security_group_ids = [var.grupo_seguranca_id]
  port                   = 5432

  storage_encrypted = true
  kms_key_id        = var.chave_kms_arn

  serverlessv2_scaling_configuration {
    min_capacity = var.acu_minima
    max_capacity = var.acu_maxima
  }

  backup_retention_period = 1
  preferred_backup_window = "06:00-07:00" # 03h em Recife
  copy_tags_to_snapshot   = true

  # Laboratório: o destroy precisa terminar sem passo manual.
  deletion_protection = false
  skip_final_snapshot = true
  apply_immediately   = true
}

resource "aws_rds_cluster_instance" "escritor" {
  identifier           = "${var.nome}-escritor"
  cluster_identifier   = aws_rds_cluster.principal.id
  instance_class       = "db.serverless"
  engine               = aws_rds_cluster.principal.engine
  engine_version       = aws_rds_cluster.principal.engine_version
  db_subnet_group_name = aws_db_subnet_group.dados.name
  publicly_accessible  = false
}

resource "aws_secretsmanager_secret" "conexao" {
  name        = "${var.nome}/banco"
  description = "Credenciais do Aurora no formato que o Prumo le em DATABASE_SECRET_ID"
  kms_key_id  = var.chave_kms_arn

  # Sem janela de recuperação: recriar o ambiente depois de um destroy não
  # esbarra no nome de um segredo "agendado para exclusão".
  recovery_window_in_days = 0
}

resource "aws_secretsmanager_secret_version" "conexao" {
  secret_id = aws_secretsmanager_secret.conexao.id
  secret_string_wo = jsonencode({
    engine   = "postgres"
    host     = aws_rds_cluster.principal.endpoint
    port     = 5432
    dbname   = var.nome_banco
    username = var.usuario_mestre
    password = ephemeral.random_password.mestre.result
  })
  secret_string_wo_version = var.versao_senha
}
