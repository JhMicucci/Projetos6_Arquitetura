# O endereço do site apontando para o CloudFront, em IPv4 e IPv6. Registro
# alias: sem custo de consulta no Route 53 e sem IP fixo para manter.

resource "aws_route53_record" "site" {
  for_each = toset(["A", "AAAA"])

  zone_id = var.zona_id
  name    = var.dominio
  type    = each.value

  alias {
    name                   = var.dominio_cloudfront
    zone_id                = var.zona_cloudfront
    evaluate_target_health = false
  }
}
