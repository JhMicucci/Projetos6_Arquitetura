# syntax=docker/dockerfile:1.7
#
# Imagens do Prumo. Dois alvos saem daqui:
#
#   execucao  (padrão)   o site: Node distroless + o servidor autocontido do
#                        Next. Sem shell, sem npm, sem gerenciador de pacotes.
#   migrador             roda `scripts/db.ts preparar` (migrações + carga da
#                        base sintética com o banco vazio) e termina. No ECS é
#                        uma tarefa avulsa antes de cada deploy; no Docker
#                        local, um serviço do docker-compose.yml.
#
# O site não migra o banco ao subir: com duas tarefas no ar, duas migrações
# concorrentes seriam um risco, e o distroless não tem `tsx`. Separar os dois é
# também menor privilégio: quem serve tráfego não altera o schema.
#
# As imagens de base vêm do espelho público do ECR (os oficiais do Docker Hub
# replicados pela AWS), para o CodeBuild não esbarrar no limite de pulls
# anônimos do Docker Hub.

ARG NODE_IMAGEM=public.ecr.aws/docker/library/node:22.23-trixie-slim
ARG EXECUCAO_IMAGEM=gcr.io/distroless/nodejs22-debian13:nonroot

# ---------------------------------------------------------------------------
# Dependências, inclusive as de desenvolvimento: o build e o `tsx` do
# migrador precisam delas. Só roda de novo quando o package-lock.json muda.
FROM ${NODE_IMAGEM} AS dependencias
WORKDIR /app
COPY package.json package-lock.json ./
RUN npm ci --no-audit --no-fund

# ---------------------------------------------------------------------------
FROM ${NODE_IMAGEM} AS build
WORKDIR /app

# NEXT_PUBLIC_* é embutido no bundle durante o build: precisa chegar aqui, não
# na execução. COMMIT_SHA vai para o /api/status, que o teste de fumaça lê.
ARG NEXT_PUBLIC_SITE_URL=""
ARG NEXT_PUBLIC_REPO_URL=""
ARG NEXT_PUBLIC_DRIVE_URL=""
ARG COMMIT_SHA="local"

ENV NEXT_TELEMETRY_DISABLED=1 \
    NEXT_OUTPUT=standalone \
    NEXT_PUBLIC_SITE_URL=${NEXT_PUBLIC_SITE_URL} \
    NEXT_PUBLIC_REPO_URL=${NEXT_PUBLIC_REPO_URL} \
    NEXT_PUBLIC_DRIVE_URL=${NEXT_PUBLIC_DRIVE_URL} \
    COMMIT_SHA=${COMMIT_SHA}

COPY --from=dependencias /app/node_modules ./node_modules
COPY . .
RUN npm run build && mkdir -p /app/cache-vazio

# ---------------------------------------------------------------------------
# Migrador, em dois passos. Primeiro o esbuild (que já vem com o `tsx`) junta
# scripts/db.ts e scripts/usuarios.ts, com tudo o que importam, num arquivo JS
# cada. Depois esses arquivos vão para a mesma base distroless do site: sem
# shell, sem npm e sem as CVEs da imagem completa do Node.
FROM ${NODE_IMAGEM} AS migrador-build
WORKDIR /app
COPY --from=dependencias /app/node_modules ./node_modules
COPY package.json tsconfig.json ./
COPY scripts ./scripts
COPY src ./src
RUN node_modules/.bin/esbuild scripts/db.ts scripts/usuarios.ts \
      --bundle --platform=node --target=node22 --format=cjs \
      --external:pg-native --outdir=dist

FROM ${EXECUCAO_IMAGEM} AS migrador
WORKDIR /app
ENV NODE_ENV=production

# As migrações são lidas de db/migrations em relação ao diretório de trabalho
# (src/lib/dados/postgres/migrar.ts).
COPY --from=migrador-build --chown=65532:65532 /app/dist/ ./
COPY --chown=65532:65532 db ./db
# Autoridades do RDS: o Aurora exige TLS e a conexão confere o certificado
# (DATABASE_SSL_CA aponta para cá, ver src/lib/dados/postgres/conexao.ts).
COPY --chown=65532:65532 certificados ./certificados

USER 65532:65532
# Padrão: migrar e, com o banco vazio, carregar a base sintética. Contas:
# `docker compose run --rm migrador usuarios.js demo`.
CMD ["db.js", "preparar"]

# ---------------------------------------------------------------------------
# Execução: o alvo padrão (o último estágio do arquivo).
FROM ${EXECUCAO_IMAGEM} AS execucao
WORKDIR /app

ARG COMMIT_SHA="local"

# CONFIG_SITE_SOMENTE_LEITURA: o contêiner roda com o sistema de arquivos
# somente leitura. A configuração do release vem de variável de ambiente e do
# Git, nunca de arquivo gravado em execução (docs/releases.md).
ENV NODE_ENV=production \
    NEXT_TELEMETRY_DISABLED=1 \
    PORT=3000 \
    HOSTNAME=0.0.0.0 \
    CONFIG_SITE_SOMENTE_LEITURA=1 \
    COMMIT_SHA=${COMMIT_SHA}

# O servidor autocontido traz só os arquivos que o rastreador do Next achou,
# inclusive os de docs/ listados em outputFileTracingIncludes. Estáticos e
# public/ não entram no rastreamento e são copiados à parte.
COPY --from=build --chown=65532:65532 /app/.next/standalone ./
COPY --from=build --chown=65532:65532 /app/.next/static ./.next/static
COPY --from=build --chown=65532:65532 /app/public ./public
COPY --chown=65532:65532 certificados ./certificados
# No ECS o sistema de arquivos é somente leitura e o cache do Next é um volume
# efêmero montado aqui. O diretório nasce VAZIO e do usuário 65532 (o cache
# do webpack do build ficaria dezenas de MB maior na imagem).
COPY --from=build --chown=65532:65532 /app/cache-vazio ./.next/cache

# 65532 é o usuário `nonroot` da imagem distroless; numérico para o
# orquestrador conferir que não é root sem ler o /etc/passwd.
USER 65532:65532
EXPOSE 3000

# A imagem distroless não tem curl nem shell: o próprio Node faz a checagem.
# A rota de saúde não consulta o banco (ver src/app/api/saude/route.ts).
HEALTHCHECK --interval=15s --timeout=5s --start-period=20s --retries=3 \
  CMD ["/nodejs/bin/node", "-e", "fetch('http://127.0.0.1:3000/api/saude').then(r=>process.exit(r.ok?0:1)).catch(()=>process.exit(1))"]

CMD ["server.js"]
