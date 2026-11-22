# CloudFront: a borda HTTPS do site, na frente do ALB.
#
# - O visitante fala HTTPS com o CloudFront (certificado do ACM, TLS 1.2+);
#   HTTP é redirecionado.
# - O app depende de cookie e da data em cada resposta (o release é calculado
#   por requisição), então o padrão é SEM CACHE e com tudo repassado à origem.
#   Só os estáticos com hash no nome (/_next/static/*) ficam em cache na borda.
# - O cabeçalho X-Origem-Verificada prova ao ALB que a requisição veio daqui.
#
# Sem WAF, por FinOps (a partir de ~US$ 5/mês mais regras). A proteção da
# origem fica com o security group e o cabeçalho secreto do ALB.

data "aws_cloudfront_cache_policy" "sem_cache" {
  name = "Managed-CachingDisabled"
}

data "aws_cloudfront_cache_policy" "estaticos" {
  name = "Managed-CachingOptimized"
}

data "aws_cloudfront_origin_request_policy" "repassa_tudo" {
  name = "Managed-AllViewer"
}

# trivy:ignore:AWS-0011
resource "aws_cloudfront_distribution" "site" {
  enabled         = true
  comment         = "Prumo: ${var.dominio}"
  aliases         = [var.dominio]
  is_ipv6_enabled = true
  http_version    = "http2and3"
  price_class     = var.classe_de_preco

  origin {
    origin_id   = "alb"
    domain_name = var.dns_origem

    custom_origin_config {
      http_port              = 80
      https_port             = 443
      origin_protocol_policy = "http-only"
      origin_ssl_protocols   = ["TLSv1.2"]
      origin_read_timeout    = 30
    }

    custom_header {
      name  = "X-Origem-Verificada"
      value = var.valor_cabecalho_origem
    }
  }

  default_cache_behavior {
    target_origin_id         = "alb"
    viewer_protocol_policy   = "redirect-to-https"
    allowed_methods          = ["GET", "HEAD", "OPTIONS", "PUT", "POST", "PATCH", "DELETE"]
    cached_methods           = ["GET", "HEAD"]
    cache_policy_id          = data.aws_cloudfront_cache_policy.sem_cache.id
    origin_request_policy_id = data.aws_cloudfront_origin_request_policy.repassa_tudo.id
    compress                 = true
  }

  ordered_cache_behavior {
    path_pattern           = "/_next/static/*"
    target_origin_id       = "alb"
    viewer_protocol_policy = "redirect-to-https"
    allowed_methods        = ["GET", "HEAD"]
    cached_methods         = ["GET", "HEAD"]
    cache_policy_id        = data.aws_cloudfront_cache_policy.estaticos.id
    compress               = true
  }

  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }

  viewer_certificate {
    acm_certificate_arn      = var.certificado_arn
    ssl_support_method       = "sni-only"
    minimum_protocol_version = "TLSv1.2_2021"
  }
}
