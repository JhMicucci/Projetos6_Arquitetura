# Certificado público do ACM para o endereço do site, validado por DNS na
# zona do Route 53. Para o CloudFront, o certificado TEM de estar em
# us-east-1; a composição do ambiente garante a região.
#
# O CAA vem antes do certificado: ele diz quais autoridades podem emitir para
# este nome. A versão da EC2 autorizava só o Let's Encrypt, o que bloquearia a
# emissão pelo ACM. Agora só a Amazon pode.

data "aws_route53_zone" "zona" {
  name         = var.zona
  private_zone = false
}

resource "aws_route53_record" "caa" {
  zone_id = data.aws_route53_zone.zona.zone_id
  name    = var.dominio
  type    = "CAA"
  ttl     = 3600
  records = [
    "0 issue \"amazon.com\"",
    "0 issue \"amazontrust.com\"",
    "0 issuewild \";\"",
  ]
}

resource "aws_acm_certificate" "site" {
  domain_name       = var.dominio
  validation_method = "DNS"

  lifecycle {
    create_before_destroy = true
  }

  depends_on = [aws_route53_record.caa]
}

resource "aws_route53_record" "validacao" {
  for_each = {
    for opcao in aws_acm_certificate.site.domain_validation_options : opcao.domain_name => opcao
  }

  zone_id         = data.aws_route53_zone.zona.zone_id
  name            = each.value.resource_record_name
  type            = each.value.resource_record_type
  records         = [each.value.resource_record_value]
  ttl             = 60
  allow_overwrite = true
}

resource "aws_acm_certificate_validation" "site" {
  certificate_arn         = aws_acm_certificate.site.arn
  validation_record_fqdns = [for registro in aws_route53_record.validacao : registro.fqdn]
}
