#!/usr/bin/env bash
# Estágio Imagem: as duas imagens do commit (site e migrador), o Trivy nas
# duas, o SBOM e o push no ECR.
#
#   <repo>:<sha>             o site (alvo `execucao` do Dockerfile)
#   <repo>:migrador-<sha>    o migrador (alvo `migrador`)
#
# Nenhuma imagem chega ao ECR sem passar pelo Trivy. As tags são imutáveis:
# reexecutar o mesmo commit reaproveita o que já está lá, mas varre de novo
# (pode ter saído CVE desde o push).
set -euo pipefail

cd "$(git rev-parse --show-toplevel 2>/dev/null || pwd)" || exit 1

: "${REPOSITORIO_ECR:?defina REPOSITORIO_ECR (conta.dkr.ecr.regiao.amazonaws.com/nome)}"
COMMIT_SHA=${COMMIT_SHA:-${CODEBUILD_RESOLVED_SOURCE_VERSION:-$(git rev-parse HEAD)}}
SEVERIDADE=${SEVERIDADE:-HIGH,CRITICAL}
RELATORIOS=${RELATORIOS:-relatorios}
JUNIT="@${TRIVY_CONTRIB:-/opt/trivy/contrib}/junit.tpl"

REGISTRO=${REPOSITORIO_ECR%%/*}
NOME_REPOSITORIO=${REPOSITORIO_ECR#*/}
REGIAO=$(echo "$REGISTRO" | cut -d. -f4)
mkdir -p "$RELATORIOS" sbom

aws ecr get-login-password --region "$REGIAO" |
  docker login --username AWS --password-stdin "$REGISTRO"

existe_no_ecr() {
  aws ecr describe-images --region "$REGIAO" --repository-name "$NOME_REPOSITORIO" \
    --image-ids imageTag="$1" >/dev/null 2>&1
}

# construir_varrer_publicar <tag> <alvo do Dockerfile>
construir_varrer_publicar() {
  local tag=$1 alvo=$2 imagem="$REPOSITORIO_ECR:$1" publicar=true

  if existe_no_ecr "$tag"; then
    echo "== $tag já está no ECR: reaproveitando e varrendo de novo"
    docker pull "$imagem"
    publicar=false
  else
    echo "== construindo $tag (alvo $alvo)"
    docker build --pull --target "$alvo" \
      --build-arg COMMIT_SHA="$COMMIT_SHA" \
      --build-arg NEXT_PUBLIC_SITE_URL="${NEXT_PUBLIC_SITE_URL:-}" \
      --build-arg NEXT_PUBLIC_REPO_URL="${NEXT_PUBLIC_REPO_URL:-}" \
      --label org.opencontainers.image.revision="$COMMIT_SHA" \
      --tag "$imagem" .
  fi

  echo "== Trivy em $tag"
  trivy image --scanners vuln,secret --severity "$SEVERIDADE" --ignore-unfixed \
    --format template --template "$JUNIT" --output "$RELATORIOS/trivy-$alvo.xml" "$imagem" >/dev/null 2>&1 || true
  trivy image --scanners vuln,secret --severity "$SEVERIDADE" --ignore-unfixed --exit-code 1 "$imagem"

  trivy image --format cyclonedx --output "sbom/$alvo.cdx.json" "$imagem"

  if [ "$publicar" = true ]; then
    docker push "$imagem"
  fi
}

# O migrador primeiro: é o menor e falha mais cedo se algo estiver errado.
construir_varrer_publicar "migrador-$COMMIT_SHA" migrador
construir_varrer_publicar "$COMMIT_SHA" execucao

docker logout "$REGISTRO" >/dev/null
echo "imagens prontas: $REPOSITORIO_ECR:{migrador-,}$COMMIT_SHA"
