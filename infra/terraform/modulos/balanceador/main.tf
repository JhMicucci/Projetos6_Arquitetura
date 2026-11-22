# Application Load Balancer nas sub-redes públicas, origem do CloudFront.
#
# Duas travas contra quem tenta pular o CloudFront e falar direto com o ALB:
#   1. Security group: a porta 80 só aceita a prefix list de origem do
#      CloudFront (módulo `grupos-seguranca`).
#   2. Cabeçalho secreto: o CloudFront manda `X-Origem-Verificada` com um valor
#      que só ele e o ALB conhecem. Sem ele, resposta 403. Isso barra também
#      uma distribuição CloudFront de OUTRA conta, que passaria pela trava 1.
#
# Listener HTTP, como no desenho: o TLS do visitante termina no CloudFront, e
# o trecho CloudFront ─> ALB corre dentro da rede da AWS.

resource "random_password" "cabecalho_origem" {
  length  = 48
  special = false
}

# Público por ser a origem do CloudFront; o security group e o cabeçalho
# secreto (acima) é que limitam quem chega.
# trivy:ignore:AWS-0053
resource "aws_lb" "principal" {
  name               = var.nome
  load_balancer_type = "application"
  internal           = false
  security_groups    = [var.grupo_seguranca_id]
  subnets            = var.subredes

  drop_invalid_header_fields = true
  enable_deletion_protection = false
  idle_timeout               = 60
}

resource "aws_lb_target_group" "app" {
  name                 = "${var.nome}-app"
  port                 = var.porta_app
  protocol             = "HTTP"
  target_type          = "ip"
  vpc_id               = var.vpc_id
  deregistration_delay = 30

  # A rota de saúde não consulta o banco: com o Aurora fora, o ALB não derruba
  # as duas tarefas ao mesmo tempo (src/app/api/saude/route.ts).
  health_check {
    path                = "/api/saude"
    matcher             = "200"
    interval            = 15
    timeout             = 5
    healthy_threshold   = 2
    unhealthy_threshold = 3
  }
}

# trivy:ignore:AWS-0054
resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.principal.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type = "fixed-response"
    fixed_response {
      content_type = "text/plain"
      message_body = "Acesso direto ao balanceador nao e permitido."
      status_code  = "403"
    }
  }
}

resource "aws_lb_listener_rule" "vindo_do_cloudfront" {
  listener_arn = aws_lb_listener.http.arn
  priority     = 1

  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.app.arn
  }

  condition {
    http_header {
      http_header_name = "X-Origem-Verificada"
      values           = [random_password.cabecalho_origem.result]
    }
  }
}
