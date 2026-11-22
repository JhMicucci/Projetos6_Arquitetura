#!/usr/bin/env bash
# Estágio Plano: `terraform plan` do ambiente com a imagem deste commit, salvo
# como artefato para a implantação aplicar EXATAMENTE o que foi planejado.
#
# Trava: o plano é recusado se destruir (ou recriar) um recurso que guarda
# dado ou identidade: o Aurora, um segredo ou a chave KMS. Uma mudança assim
# é feita à mão, de propósito, e nunca por um push.
set -euo pipefail

cd "$(git rev-parse --show-toplevel 2>/dev/null || pwd)" || exit 1

: "${TF_STATE_BUCKET:?defina TF_STATE_BUCKET}"
: "${TF_STATE_REGIAO:?defina TF_STATE_REGIAO}"
: "${COMMIT_SHA:?defina COMMIT_SHA}"

RAIZ=infra/terraform/ambientes/producao
PROTEGIDOS="aws_rds_cluster aws_rds_cluster_instance aws_secretsmanager_secret aws_kms_key"

terraform -chdir="$RAIZ" init -input=false -no-color \
  -backend-config="bucket=$TF_STATE_BUCKET" -backend-config="region=$TF_STATE_REGIAO"

terraform -chdir="$RAIZ" plan -input=false -no-color -lock-timeout=5m \
  -var "versao_imagem=$COMMIT_SHA" -out=tfplan

terraform -chdir="$RAIZ" show -json tfplan >plano.json

contar() { jq "[.resource_changes[]? | select(.change.actions == $1)] | length" plano.json; }
CRIAR=$(contar '["create"]')
MUDAR=$(contar '["update"]')
DESTRUIR=$(contar '["delete"]')
RECRIAR=$(jq '[.resource_changes[]? | select((.change.actions | index("delete")) and (.change.actions | index("create")))] | length' plano.json)
echo "Plano: criar $CRIAR, alterar $MUDAR, recriar $RECRIAR, destruir $DESTRUIR" | tee plano-resumo.txt

PERIGOSOS=$(jq -r --arg tipos "$PROTEGIDOS" '
  ($tipos | split(" ")) as $protegidos
  | .resource_changes[]?
  | select(.change.actions | index("delete"))
  | select(.type as $t | $protegidos | index($t))
  | .address' plano.json)

if [ -n "$PERIGOSOS" ]; then
  echo
  echo "PLANO RECUSADO: ele destruiria ou recriaria recurso protegido:"
  while IFS= read -r endereco; do echo "  - $endereco"; done <<<"$PERIGOSOS"
  echo "Se for intencional, aplique à mão, fora do pipeline (docs/pipeline.md)."
  exit 1
fi
