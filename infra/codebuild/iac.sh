#!/usr/bin/env bash
# Fitness functions da infraestrutura como código. Todas rodam e o script só
# reprova no fim, com a lista do que falhou.
#
#   bash infra/codebuild/ferramentas.sh trivy terraform tflint tflint_aws
#   bash infra/codebuild/iac.sh
set -uo pipefail

cd "$(git rev-parse --show-toplevel 2>/dev/null || pwd)" || exit 1

RELATORIOS=${RELATORIOS:-relatorios}
SEVERIDADE=${SEVERIDADE:-HIGH,CRITICAL}
JUNIT="@${TRIVY_CONTRIB:-/opt/trivy/contrib}/junit.tpl"
RAIZES=(infra/terraform/bootstrap infra/terraform/cicd infra/terraform/ambientes/producao)
mkdir -p "$RELATORIOS"

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

# 1. Formatação canônica: diff de estilo não entra misturado com mudança real.
formatado() {
  terraform fmt -check -recursive -diff infra/terraform
}

# 2. Cada raiz válida contra o schema real dos providers (sem tocar na AWS).
valido() {
  local raiz
  for raiz in "${RAIZES[@]}"; do
    echo "-- $raiz"
    terraform -chdir="$raiz" init -backend=false -input=false -no-color >/dev/null || return 1
    terraform -chdir="$raiz" validate -no-color || return 1
  done
}

# 3. TFLint: erros que o validate não pega (tipo de instância inexistente,
#    variável sem tipo, declaração sem uso) e as regras da AWS.
sem_alerta_do_tflint() {
  tflint --init --config "$PWD/.tflint.hcl" >/dev/null || return 1
  tflint --chdir=infra/terraform --recursive --config "$PWD/.tflint.hcl" --format compact
}

# 4. Sem configuração insegura alta ou crítica no Terraform e no Dockerfile.
#    Exceção só por comentário `trivy:ignore` com a justificativa ao lado.
sem_configuracao_insegura() {
  local resultado=0
  trivy config --severity "$SEVERIDADE" --skip-dirs "node_modules,.next,**/.terraform" --exit-code 1 . || resultado=$?
  trivy config --severity "$SEVERIDADE" --skip-dirs "node_modules,.next,**/.terraform" \
    --format template --template "$JUNIT" --output "$RELATORIOS/trivy-iac.xml" . >/dev/null 2>&1
  return "$resultado"
}

etapa "terraform formatado" formatado
etapa "terraform valido (bootstrap, cicd, ambiente)" valido
etapa "tflint sem alerta" sem_alerta_do_tflint
etapa "IaC sem configuracao insegura (trivy config)" sem_configuracao_insegura

printf '\n===================================\n'
if [ "${#falhas[@]}" -gt 0 ]; then
  printf 'Reprovado em %d fitness function(s):\n' "${#falhas[@]}"
  printf '  - %s\n' "${falhas[@]}"
  exit 1
fi
echo "Todas as fitness functions de IaC passaram."
