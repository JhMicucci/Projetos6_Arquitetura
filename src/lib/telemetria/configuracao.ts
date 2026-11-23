import type { IncomingMessage } from 'node:http'
import { HttpInstrumentation } from '@opentelemetry/instrumentation-http'
import { PgInstrumentation, type PgInstrumentationConfig } from '@opentelemetry/instrumentation-pg'

/**
 * O que é instrumentado, num lugar só. A produção (`iniciar.ts`) e a fitness
 * function de observabilidade (`scripts/sonda-telemetria.ts`) importam DAQUI:
 * o teste prova a configuração que vai para o ar, não uma cópia dela.
 */

/**
 * O banco no trace.
 * - `enhancedDatabaseReporting: false` é o que impede os VALORES da consulta
 *   de irem para o atributo `db.postgresql.values`. Fica explícito, e não no
 *   padrão, porque é a linha que segura a regra 1 do CLAUDE.md.
 * - `requireParentSpan: true`: só entra consulta feita dentro de uma
 *   requisição. Cada span do banco fica pendurado no trace de quem o causou.
 * - `ignoreConnectSpans: true`: pegar uma conexão do pool não vira span. No
 *   teste com um Collector de verdade, eram 91 spans `pg-pool.connect` para 3
 *   requisições, só ruído no Tempo e volume a mais para guardar.
 */
export const CONFIG_PG: PgInstrumentationConfig = {
  enhancedDatabaseReporting: true, // E21 (teste de reprovação): valores da consulta no trace
  requireParentSpan: true,
  ignoreConnectSpans: true,
}

/**
 * Requisições que não viram trace: a checagem de vida do ALB (uma a cada
 * poucos segundos, em cada tarefa) e os estáticos com hash no nome.
 */
const PREFIXOS_IGNORADOS = ['/api/saude', '/_next/static/', '/favicon.ico']

export function requisicaoIgnorada(url: string | undefined): boolean {
  return PREFIXOS_IGNORADOS.some((prefixo) => (url ?? '').startsWith(prefixo))
}

export function instrumentacaoDoBanco(): PgInstrumentation {
  return new PgInstrumentation(CONFIG_PG)
}

export function instrumentacoes(): Array<HttpInstrumentation | PgInstrumentation> {
  return [
    new HttpInstrumentation({
      ignoreIncomingRequestHook: (requisicao: IncomingMessage) => requisicaoIgnorada(requisicao.url),
    }),
    instrumentacaoDoBanco(),
  ]
}
