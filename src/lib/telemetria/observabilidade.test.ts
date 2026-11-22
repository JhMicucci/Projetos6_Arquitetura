import { execFileSync } from 'node:child_process'
import { randomBytes } from 'node:crypto'
import { createRequire } from 'node:module'
import { Client } from 'pg'
import { afterAll, beforeAll, describe, expect, it } from 'vitest'

/**
 * FITNESS FUNCTION DE OBSERVABILIDADE.
 *
 * A propriedade que este teste defende: uma escrita no sistema aparece no
 * trace até o banco, e o que a pessoa digitou não aparece em lugar nenhum da
 * telemetria. É a mesma ideia da fitness function da Notas da Nuvem (o span do
 * INSERT existe e o texto da nota não vaza), aplicada ao lançamento do Prumo.
 *
 * Uma refatoração que tire a consulta do contexto da requisição (uma fila,
 * uma thread, um `setTimeout`), que ligue o registro de valores ou que monte o
 * SQL concatenando texto quebra aqui, antes de chegar à produção.
 *
 * Roda num banco PRÓPRIO, criado e apagado aqui, porque o teste do driver
 * recria o schema do banco de teste. Sem `DATABASE_URL_TESTE`, é pulado.
 */

const URL_TESTE = process.env.DATABASE_URL_TESTE
const BANCO_DA_SONDA = 'prumo_telemetria'
const MARCADOR = `MARCADOR-PRIVADO-${randomBytes(6).toString('hex')}`

interface SpanDaSonda {
  nome: string
  tipo: number
  traceId: string
  spanId: string
  paiId: string | null
  escopo: string
  atributos: Record<string, unknown>
  eventos: Array<{ nome: string; atributos: Record<string, unknown> }>
}

const SERVIDOR = 1 // SpanKind.SERVER
const CLIENTE = 2 // SpanKind.CLIENT

function urlDoBanco(url: string, banco: string): string {
  const destino = new URL(url)
  destino.pathname = `/${banco}`
  return destino.toString()
}

async function comAdmin(sql: string): Promise<void> {
  const admin = new Client({ connectionString: URL_TESTE })
  await admin.connect()
  try {
    await admin.query(sql)
  } finally {
    await admin.end()
  }
}

let spans: SpanDaSonda[] = []

const textoDaConsulta = (s: SpanDaSonda) =>
  String(s.atributos['db.query.text'] ?? s.atributos['db.statement'] ?? '')

const ehDoBanco = (s: SpanDaSonda) =>
  s.tipo === CLIENTE &&
  (s.atributos['db.system.name'] === 'postgresql' || s.atributos['db.system'] === 'postgresql')

describe.skipIf(!URL_TESTE)('fitness function de observabilidade', () => {
  beforeAll(async () => {
    await comAdmin(`drop database if exists ${BANCO_DA_SONDA} with (force)`)
    await comAdmin(`create database ${BANCO_DA_SONDA}`)

    const tsx = createRequire(import.meta.url).resolve('tsx/cli')
    const saida = execFileSync(process.execPath, [tsx, 'scripts/sonda-telemetria.ts'], {
      env: { ...process.env, DATABASE_URL_SONDA: urlDoBanco(URL_TESTE!, BANCO_DA_SONDA), MARCADOR },
      encoding: 'utf8',
      timeout: 120_000,
    })
    const linha = saida.split('\n').find((l) => l.startsWith('SPANS='))
    if (!linha) throw new Error(`A sonda não imprimiu os spans. Saída:\n${saida}`)
    spans = JSON.parse(linha.slice('SPANS='.length)) as SpanDaSonda[]
  }, 180_000)

  afterAll(async () => {
    if (URL_TESTE) await comAdmin(`drop database if exists ${BANCO_DA_SONDA} with (force)`)
  })

  it('o lançamento gera o span do INSERT, dentro do trace da requisição', () => {
    const requisicao = spans.find((s) => s.tipo === SERVIDOR)
    expect(requisicao, 'span da requisição').toBeDefined()

    const doBanco = spans.filter(ehDoBanco)
    const nomes = spans.map((s) => s.nome)
    expect(doBanco.length, `nenhum span do banco foi gerado: ${JSON.stringify(nomes)}`).toBeGreaterThan(0)

    const insert = doBanco.find((s) => /\binsert\s+into\b/i.test(textoDaConsulta(s)))
    expect(insert, `nenhum span do INSERT foi gerado: ${JSON.stringify(nomes)}`).toBeDefined()

    // Mesmo trace, e pendurado na requisição: é isso que liga o POST ao banco
    // no Tempo. Uma consulta fora do contexto da requisição não teria pai.
    for (const s of doBanco) {
      expect(s.traceId).toBe(requisicao!.traceId)
      expect(s.paiId).not.toBeNull()
    }
  })

  it('a consulta vai parametrizada para a telemetria', () => {
    const insert = spans.filter(ehDoBanco).find((s) => /\binsert\s+into\b/i.test(textoDaConsulta(s)))!
    expect(textoDaConsulta(insert)).toMatch(/\$1\b/)
    expect(insert.atributos['db.postgresql.values']).toBeUndefined()
  })

  it('o texto digitado não vaza para nenhum span, atributo ou evento', () => {
    expect(JSON.stringify(spans)).not.toContain(MARCADOR)
  })

  it('a query string da URL sai do span da requisição', () => {
    const requisicao = spans.find((s) => s.tipo === SERVIDOR)!
    expect(String(requisicao.atributos['url.full'])).not.toContain('?')
  })
})
