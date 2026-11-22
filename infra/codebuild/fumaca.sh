#!/usr/bin/env bash
# Estágio Fumaça: fitness functions de produção, medidas de fora, pela
# internet, contra o que acabou de subir. Validam o que nenhum teste local
# alcança: o certificado real, os security groups reais, a versão real.
#
# Uso local: URL_SITE=https://app.exemplo COMMIT_SHA=<sha> DNS_ALB=<dns> \
#            IP_OBSERVABILIDADE=<ip> bash infra/codebuild/fumaca.sh
set -uo pipefail

: "${URL_SITE:?defina URL_SITE}"
COMMIT_SHA=${COMMIT_SHA:-}
DNS_ALB=${DNS_ALB:-}
IP_OBSERVABILIDADE=${IP_OBSERVABILIDADE:-}
DOMINIO=${URL_SITE#https://}
ESPERA_MAXIMA_S=${ESPERA_MAXIMA_S:-600}

falhas=()
etapa() {
  local nome=$1
  shift
  printf '\n=== %s\n' "$nome"
  if "$@"; then
    printf -- '--- ok: %s\n' "$nome"
  else
    printf -- '--- FALHOU: %s\n' "$nome"
    falhas+=("$nome")
  fi
}

# 1. A versão no ar é a do commit. Espera porque, na primeira criação, o
#    CloudFront leva minutos para propagar o domínio.
versao_no_ar() {
  local esperado=${COMMIT_SHA:0:7} limite=$((SECONDS + ESPERA_MAXIMA_S)) corpo commit
  while [ "$SECONDS" -lt "$limite" ]; do
    if corpo=$(curl -fsS --max-time 10 "$URL_SITE/api/saude" 2>/dev/null); then
      commit=$(echo "$corpo" | sed -n 's/.*"commit":"\([^"]*\)".*/\1/p')
      if [ -z "$esperado" ] || [ "$commit" = "$esperado" ]; then
        echo "no ar: commit $commit"
        return 0
      fi
      echo "no ar: $commit; esperando $esperado"
    else
      echo "ainda sem resposta em $URL_SITE"
    fi
    sleep 15
  done
  return 1
}

# 2. O caminho inteiro até o banco: o /api/status consulta o Aurora.
banco_respondendo() {
  local corpo
  corpo=$(curl -fsS --max-time 20 "$URL_SITE/api/status") || return 1
  echo "$corpo" | grep -q '"ok":true' && echo "$corpo" | grep -o '"modoDeDados":"[^"]*"'
}

# 3. Certificado aceito por um cliente comum e com mais de 14 dias de folga.
certificado_valido() {
  echo | openssl s_client -servername "$DOMINIO" -connect "$DOMINIO:443" -verify_return_error 2>/dev/null |
    openssl x509 -noout -subject -issuer -enddate -checkend $((14 * 24 * 3600))
}

# 4. HTTP nunca serve a página: o CloudFront redireciona para HTTPS.
http_redireciona() {
  local resposta codigo destino
  resposta=$(curl -s -o /dev/null --max-time 10 -w '%{http_code} %{redirect_url}' "http://$DOMINIO/")
  codigo=${resposta%% *}
  destino=${resposta#* }
  echo "http -> $codigo $destino"
  [[ "$codigo" =~ ^30[1278]$ ]] && [[ "$destino" == https://* ]]
}

# 5. Os cabeçalhos de segurança do next.config.ts chegam ao navegador, e o
#    framework não se anuncia. (Via e X-Cache são do CloudFront e a AWS não
#    deixa removê-los; não entram aqui.)
cabecalhos_de_seguranca() {
  local cabecalhos ok=0 nome
  cabecalhos=$(curl -fsS -D - -o /dev/null --max-time 15 "$URL_SITE/" | tr -d '\r' | tr '[:upper:]' '[:lower:]')
  for nome in strict-transport-security content-security-policy x-frame-options x-content-type-options referrer-policy permissions-policy; do
    if grep -q "^$nome:" <<<"$cabecalhos"; then echo "presente: $nome"; else echo "AUSENTE: $nome"; ok=1; fi
  done
  if grep -q "^x-powered-by:" <<<"$cabecalhos"; then echo "VAZA: x-powered-by"; ok=1; fi
  return "$ok"
}

# 6. Ninguém fala com o ALB pulando o CloudFront: daqui (fora da prefix list
#    de origem) a conexão nem abre, e mesmo de dentro faltaria o cabeçalho.
alb_recusa_acesso_direto() {
  [ -n "$DNS_ALB" ] || { echo "DNS_ALB não informado"; return 1; }
  local codigo
  codigo=$(curl -s -o /dev/null --max-time 10 -w '%{http_code}' "http://$DNS_ALB/")
  echo "acesso direto ao ALB -> ${codigo} (000 = conexão recusada pelo security group)"
  [[ ! "$codigo" =~ ^[23] ]]
}

# 7. A observabilidade não está aberta para a internet: o Grafana só aceita o
#    IP do administrador, o OTLP só as tarefas, e não existe SSH.
observabilidade_fechada() {
  [ -n "$IP_OBSERVABILIDADE" ] || { echo "IP_OBSERVABILIDADE não informado"; return 1; }
  local ok=0 porta
  for porta in 22 3000 4318; do
    if timeout 5 bash -c "</dev/tcp/$IP_OBSERVABILIDADE/$porta" 2>/dev/null; then
      echo "ABERTA para a internet: $porta"
      ok=1
    else
      echo "fechada (esperado): $porta"
    fi
  done
  return "$ok"
}

etapa "versao no ar e a do commit" versao_no_ar
etapa "banco respondendo pelo site" banco_respondendo
etapa "certificado TLS valido" certificado_valido
etapa "HTTP redireciona para HTTPS" http_redireciona
etapa "cabecalhos de seguranca" cabecalhos_de_seguranca
etapa "ALB recusa acesso direto" alb_recusa_acesso_direto
etapa "observabilidade fechada para a internet" observabilidade_fechada

printf '\n===================================\n'
if [ "${#falhas[@]}" -gt 0 ]; then
  printf 'Producao reprovada em %d verificacao(oes):\n' "${#falhas[@]}"
  printf '  - %s\n' "${falhas[@]}"
  exit 1
fi
echo "Producao conferida: $URL_SITE"
