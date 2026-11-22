/**
 * Sonda da fitness function de observabilidade.
 *
 * Não é para rodar à mão: `src/lib/telemetria/observabilidade.test.ts` sobe
 * este script num processo próprio, com um banco descartável, e lê os spans
 * que ele imprime. Processo próprio porque a instrumentação do `pg` se acopla
 * no `require`: dentro do Vitest, o módulo já carregado por outro teste
 * escaparia dela, e o teste passaria sem provar nada.
 *
 * O que a sonda faz é o caminho de uma requisição de verdade: abre um span de
 * servidor (como o da instrumentação HTTP) e, dentro dele, registra um
 * lançamento pelo MESMO driver que as telas usam, com a MESMA configuração de
 * telemetria da produção. A evidência leva um marcador único; o teste confere
 * que o INSERT aparece no trace e que o marcador não aparece em lugar nenhum.
 *
 * Ambiente: DATABASE_URL_SONDA (banco vazio e descartável) e MARCADOR.
 */
import { SpanKind, SpanStatusCode, trace } from '@opentelemetry/api'
import { NodeSDK } from '@opentelemetry/sdk-node'
import { InMemorySpanExporter, SimpleSpanProcessor } from '@opentelemetry/sdk-trace'
import { instrumentacaoDoBanco } from '../src/lib/telemetria/configuracao'
import { ProcessadorDePrivacidade } from '../src/lib/telemetria/privacidade'

const URL_SONDA = process.env.DATABASE_URL_SONDA
const MARCADOR = process.env.MARCADOR
if (!URL_SONDA || !MARCADOR) {
  console.error('Faltam DATABASE_URL_SONDA e MARCADOR.')
  process.exit(2)
}

const exportador = new InMemorySpanExporter()
const sdk = new NodeSDK({
  serviceName: 'prumo-sonda',
  spanProcessors: [new ProcessadorDePrivacidade(), new SimpleSpanProcessor({ exporter: exportador })],
  instrumentations: [instrumentacaoDoBanco()],
  metricReaders: [],
  logRecordProcessors: [],
})
sdk.start()

// Só DEPOIS do sdk.start(): é no `require` que a instrumentação se acopla ao
// `pg`. Por isso `require`, e não `import` (que o compilador sobe para o topo).
/* eslint-disable @typescript-eslint/no-require-imports */
const { Pool } = require('pg') as typeof import('pg')
const { aplicarMigracoes } = require('../src/lib/dados/postgres/migrar') as typeof import('../src/lib/dados/postgres/migrar')
const { carregarBase } = require('../src/lib/dados/postgres/carga') as typeof import('../src/lib/dados/postgres/carga')
const { bancoDoPool } = require('../src/lib/dados/postgres/conexao') as typeof import('../src/lib/dados/postgres/conexao')
const { driverPostgres } = require('../src/lib/dados/driver-postgres') as typeof import('../src/lib/dados/driver-postgres')
const { BASE } = require('../src/lib/seed') as typeof import('../src/lib/seed')
/* eslint-enable @typescript-eslint/no-require-imports */

async function principal(): Promise<void> {
  const pool = new Pool({ connectionString: URL_SONDA, max: 2 })
  try {
    // Preparação fora de qualquer span: com `requireParentSpan`, nada disto
    // entra na telemetria. A limpeza abaixo é cinto e suspensório.
    const cliente = await pool.connect()
    try {
      await aplicarMigracoes(cliente)
      await cliente.query('begin')
      await carregarBase(cliente, BASE)
      await cliente.query('commit')
    } finally {
      cliente.release()
    }
    exportador.reset()

    const driver = driverPostgres(bancoDoPool(pool))
    const tracer = trace.getTracer('sonda')
    await tracer.startActiveSpan(
      'POST /api/sistema/lancamento',
      {
        kind: SpanKind.SERVER,
        // A URL com o marcador na query: o processador de privacidade tem de tirá-la.
        attributes: {
          'http.request.method': 'POST',
          'url.full': `http://sonda.local/api/sistema/lancamento?evidencia=${MARCADOR}`,
          'url.query': `evidencia=${MARCADOR}`,
        },
      },
      async (span) => {
        try {
          const resultado = await driver.registrarLancamento(
            {
              subindicadorId: 'acompanhamento-familias',
              unidadeId: 'usf-canario',
              cicloId: 'ciclo-2026-07',
              valor: null,
              numerador: 170,
              denominador: 200,
              evidencia: `relatório da sonda ${MARCADOR}`,
              autor: 'ger-usf-canario',
              perfil: 'gerente_unidade',
            },
            '2026-07-15T13:00:00.000Z',
          )
          if (!resultado.ok) throw new Error(`lançamento recusado: ${resultado.mensagem}`)
        } catch (erro) {
          span.setStatus({ code: SpanStatusCode.ERROR })
          throw erro
        } finally {
          span.end()
        }
      },
    )

    const spans = exportador.getFinishedSpans().map((s) => ({
      nome: s.name,
      tipo: s.kind,
      traceId: s.spanContext().traceId,
      spanId: s.spanContext().spanId,
      paiId: s.parentSpanContext?.spanId ?? null,
      escopo: s.instrumentationScope.name,
      atributos: s.attributes,
      eventos: s.events.map((e) => ({ nome: e.name, atributos: e.attributes ?? {} })),
    }))
    console.log(`SPANS=${JSON.stringify(spans)}`)
  } finally {
    await pool.end()
    await sdk.shutdown()
  }
}

principal().catch((erro) => {
  console.error(erro instanceof Error ? erro.stack : String(erro))
  process.exit(1)
})
