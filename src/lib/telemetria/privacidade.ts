import type { Span, SpanProcessor } from '@opentelemetry/sdk-trace'

/**
 * A telemetria segue a regra 1 do CLAUDE.md: dado de pessoa não entra nela,
 * nem por acidente. Três frentes, cada uma com teste:
 *
 * 1. CONSULTA: o banco aparece no trace com o SQL parametrizado (`$1`, `$2`),
 *    nunca com os valores. Ver `CONFIG_PG` em `configuracao.ts`.
 * 2. URL: a query string sai de todo span, inclusive dos que o próprio Next
 *    cria. Os parâmetros da URL do /sistema escolhem perfil e unidade; hoje
 *    não identificam ninguém, mas a regra não pode depender de "hoje".
 * 3. ERRO: o registro leva a rota e o tipo do erro; o que vier entre aspas na
 *    mensagem (o Postgres cita o valor recusado) é redigido.
 */

/**
 * Valor com cara de caminho ou URL: `/sistema?x`, `https://host/x?y` ou
 * `GET /sistema?x` (o formato do nome dos spans do Next). SQL não casa: começa
 * por `select`, `insert`, e não por barra.
 */
const PARECE_URL = /^(?:[A-Z]+ )?(?:\/|https?:\/\/)/

/** Atributo da query string isolada, na convenção estável. */
const ATRIBUTO_QUERY = 'url.query'

export const QUERY_REDIGIDA = '[redigida]'

/** A URL sem a query string (o fragmento também sai, se houver). */
export function semQuery(url: string): string {
  const corte = url.search(/[?#]/)
  return corte === -1 ? url : url.slice(0, corte)
}

/**
 * Mensagem de erro segura para a telemetria: o que está entre aspas some, e o
 * detalhe do Postgres no formato `(coluna)=(valor)` perde o valor. Corta no
 * limite para um stack trace não virar log de quilobytes.
 */
export function redigirMensagem(texto: string, limite = 300): string {
  return texto
    .replace(/"[^"]*"/g, '"[redigido]"')
    .replace(/'[^']*'/g, "'[redigido]'")
    .replace(/\(([^()]*)\)=\(([^()]*)\)/g, '($1)=([redigido])')
    .slice(0, limite)
}

/** Tira a query string de um valor só se ele tiver cara de caminho ou URL. */
export function limparValor(valor: string): string {
  return PARECE_URL.test(valor) && /[?#]/.test(valor) ? semQuery(valor) : valor
}

/**
 * Vale para o NOME e para TODO atributo de texto, e não para uma lista de
 * chaves conhecidas. A lista fixa já falhou duas vezes, vistas num Collector
 * de verdade: o Next põe a URL inteira no nome do span raiz e no atributo
 * próprio `next.span_name`, que nenhuma convenção previa.
 */
function limparUrls(span: Span): void {
  const nome = limparValor(span.name)
  if (nome !== span.name) span.updateName(nome)

  for (const [chave, valor] of Object.entries(span.attributes)) {
    if (chave === ATRIBUTO_QUERY || typeof valor !== 'string') continue
    const limpo = limparValor(valor)
    if (limpo !== valor) span.setAttribute(chave, limpo)
  }
  const query = span.attributes[ATRIBUTO_QUERY]
  if (typeof query === 'string' && query !== '' && query !== QUERY_REDIGIDA) {
    span.setAttribute(ATRIBUTO_QUERY, QUERY_REDIGIDA)
  }
}

/**
 * Limpa as URLs de todo span, no começo e de novo antes de fechar (`onEnding`):
 * há instrumentação que grava atributo depois de abrir o span. Fica na frente
 * do exportador na lista de processadores, mas a ordem não importa: o
 * exportador só lê o span quando ele termina.
 */
export class ProcessadorDePrivacidade implements SpanProcessor {
  onStart(span: Span): void {
    limparUrls(span)
  }

  onEnding(span: Span): void {
    limparUrls(span)
  }

  onEnd(): void {}

  forceFlush(): Promise<void> {
    return Promise.resolve()
  }

  shutdown(): Promise<void> {
    return Promise.resolve()
  }
}
