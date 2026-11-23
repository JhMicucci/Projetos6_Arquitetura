#!/usr/bin/env bash
# Instala as ferramentas do pipeline com versão fixa e SHA-256 conferido. É o
# único lugar com versões de ferramenta: para atualizar, troque versão e hash
# juntos, tirando o hash do arquivo de checksums publicado no release.
#
# Uso: ferramentas.sh trivy gitleaks hadolint terraform tflint tflint_aws
set -euo pipefail

TRIVY_VERSAO=0.76.2
TRIVY_SHA256=bc0fc726e017b8927a62b2d3531d7a84ee01769daf5c99ed866dced54089fdbf

GITLEAKS_VERSAO=8.30.1
GITLEAKS_SHA256=551f6fc83ea457d62a0d98237cbad105af8d557003051f41f3e7ca7b3f2470eb

HADOLINT_VERSAO=2.15.1
HADOLINT_SHA256=c7187db94eeeeca956519a6af171adc31453941a1e777961f6e680f697c8c507

TERRAFORM_VERSAO=1.17.1
TERRAFORM_SHA256=4638628058e71a55212b1c563712eac03b902128f40740f3dc8174df12135061

TFLINT_VERSAO=0.65.0
TFLINT_SHA256=d4c545ed2e29d6338604b586f34f544f380f70f243aa72f7b484713835eaec61

# A versão tem de ser a mesma do bloco plugin "aws" em .tflint.hcl.
TFLINT_AWS_VERSAO=0.50.0
TFLINT_AWS_SHA256=cdd433fdbc0929e7b9f9709dd9e72237fdfe1fc235674445c284b1e4b94a5c26

DESTINO=${DESTINO:-/usr/local/bin}
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

# baixar <url> <arquivo> <sha256>: falha se o hash não bater.
baixar() {
  curl -fsSL --retry 3 --retry-delay 2 -o "$TMP/$2" "$1"
  echo "$3  $TMP/$2" | sha256sum --check --quiet -
}

instalar_trivy() {
  baixar "https://github.com/aquasecurity/trivy/releases/download/v${TRIVY_VERSAO}/trivy_${TRIVY_VERSAO}_Linux-64bit.tar.gz" trivy.tgz "$TRIVY_SHA256"
  tar -xzf "$TMP/trivy.tgz" -C "$TMP" trivy contrib
  install -m 0755 "$TMP/trivy" "$DESTINO/trivy"
  # Os templates (junit.tpl) servem aos relatórios do CodeBuild.
  mkdir -p /opt/trivy && cp -r "$TMP/contrib" /opt/trivy/
}

instalar_gitleaks() {
  baixar "https://github.com/gitleaks/gitleaks/releases/download/v${GITLEAKS_VERSAO}/gitleaks_${GITLEAKS_VERSAO}_linux_x64.tar.gz" gitleaks.tgz "$GITLEAKS_SHA256"
  tar -xzf "$TMP/gitleaks.tgz" -C "$TMP" gitleaks
  install -m 0755 "$TMP/gitleaks" "$DESTINO/gitleaks"
}

instalar_hadolint() {
  baixar "https://github.com/hadolint/hadolint/releases/download/v${HADOLINT_VERSAO}/hadolint-linux-x86_64" hadolint "$HADOLINT_SHA256"
  install -m 0755 "$TMP/hadolint" "$DESTINO/hadolint"
}

instalar_terraform() {
  baixar "https://releases.hashicorp.com/terraform/${TERRAFORM_VERSAO}/terraform_${TERRAFORM_VERSAO}_linux_amd64.zip" terraform.zip "$TERRAFORM_SHA256"
  unzip -oq "$TMP/terraform.zip" terraform -d "$TMP"
  install -m 0755 "$TMP/terraform" "$DESTINO/terraform"
}

instalar_tflint() {
  baixar "https://github.com/terraform-linters/tflint/releases/download/v${TFLINT_VERSAO}/tflint_linux_amd64.zip" tflint.zip "$TFLINT_SHA256"
  unzip -oq "$TMP/tflint.zip" tflint -d "$TMP"
  install -m 0755 "$TMP/tflint" "$DESTINO/tflint"
}

# O plugin da AWS do TFLint. Sem ele já instalado, o `tflint --init` consulta a
# API do GitHub, que sem token aceita 60 chamadas por hora por IP; o IP do
# CodeBuild é compartilhado e o limite estoura (403 rate limit exceeded). O
# download do release não passa por essa API. Fica onde o `--init` procura,
# e ele passa a ver o plugin instalado e não chama a rede.
instalar_tflint_aws() {
  local dir="${TFLINT_PLUGIN_DIR:-$HOME/.tflint.d/plugins}/github.com/terraform-linters/tflint-ruleset-aws/${TFLINT_AWS_VERSAO}"
  baixar "https://github.com/terraform-linters/tflint-ruleset-aws/releases/download/v${TFLINT_AWS_VERSAO}/tflint-ruleset-aws_linux_amd64.zip" tflint-aws.zip "$TFLINT_AWS_SHA256"
  mkdir -p "$dir"
  unzip -oq "$TMP/tflint-aws.zip" tflint-ruleset-aws -d "$TMP"
  install -m 0755 "$TMP/tflint-ruleset-aws" "$dir/tflint-ruleset-aws"
}

for ferramenta in "$@"; do
  "instalar_${ferramenta}"
  echo "instalado: ${ferramenta}"
done
