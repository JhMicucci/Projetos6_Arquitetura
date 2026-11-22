import { SpanKind } from '@opentelemetry/api'
import { InMemorySpanExporter, SimpleSpanProcessor, TracerProvider } from '@opentelemetry/sdk-trace'
import { describe, expect, it } from 'vitest'
import { CONFIG_PG, requisicaoIgnorada } from './configuracao'
import { ProcessadorDePrivacidade, QUERY_REDIGIDA, redigirMensagem, semQuery } from './privacidade'

describe('semQuery', () => {
  it('tira a query string e o fragmento, e deixa o caminho', () => {
    expect(semQuery('https://app.exemplo/sistema?perfil=seab&unidade=usf-canario')).toBe(
      'https://app.exemplo/sistema',
    )
    expect(semQuery('/sistema#lancamento')).toBe('/sistema')
    expect(semQuery('/sistema')).toBe('/sistema')
  })
})

describe('redigirMensagem', () => {
  it('redige o que vem entre aspas', () => {
    expect(redigirMensagem('invalid input syntax for type integer: "abc123"')).toBe(
      'invalid input syntax for type integer: "[redigido]"',
    )
    expect(redigirMensagem("valor 'segredo' recusado")).toBe("valor '[redigido]' recusado")
  })

  it('redige o valor do detalhe do Postgres e mantém a coluna', () => {
    expect(redigirMensagem('Key (login)=(ger-usf-canario) already exists.')).toBe(
      'Key (login)=([redigido]) already exists.',
    )
  })

  it('corta mensagens longas', () => {
    expect(redigirMensagem('x'.repeat(1000))).toHaveLength(300)
  })
})

describe('ProcessadorDePrivacidade', () => {
  function exportarSpan(nome: string, atributos: Record<string, string>, depois?: Record<string, string>) {
    const exportador = new InMemorySpanExporter()
    const provedor = new TracerProvider({
      spanProcessors: [new ProcessadorDePrivacidade(), new SimpleSpanProcessor({ exporter: exportador })],
    })
    const span = provedor.getTracer('teste').startSpan(nome, { kind: SpanKind.SERVER, attributes: atributos })
    if (depois) span.setAttributes(depois)
    span.end()
    return exportador.getFinishedSpans()[0]
  }

  const exportarUmSpan = (atributos: Record<string, string>, depois?: Record<string, string>) =>
    exportarSpan('GET /sistema', atributos, depois).attributes

  it('tira a query string do NOME do span e de atributos próprios do Next', () => {
    // Casos reais, vistos num Collector: o span raiz do Next chegava assim.
    const span = exportarSpan('GET /sistema?perfil=seab&unidade=usf-canario', {
      'next.span_name': 'GET /sistema?perfil=seab&unidade=usf-canario',
    })
    expect(span.name).toBe('GET /sistema')
    expect(span.attributes['next.span_name']).toBe('GET /sistema')
  })

  it('não mexe em SQL nem em texto que não é URL', () => {
    const atributos = exportarUmSpan({
      'db.query.text': 'select * from lancamentos where id = $1',
      'exception.message': 'o que é isto?',
    })
    expect(atributos['db.query.text']).toBe('select * from lancamentos where id = $1')
    expect(atributos['exception.message']).toBe('o que é isto?')
  })

  it('tira a query string das URLs gravadas na abertura do span', () => {
    const atributos = exportarUmSpan({
      'url.full': 'https://app.exemplo/sistema?perfil=seab',
      'http.target': '/sistema?perfil=seab',
      'url.query': 'perfil=seab',
      'url.path': '/sistema',
    })
    expect(atributos['url.full']).toBe('https://app.exemplo/sistema')
    expect(atributos['http.target']).toBe('/sistema')
    expect(atributos['url.query']).toBe(QUERY_REDIGIDA)
    expect(atributos['url.path']).toBe('/sistema')
  })

  it('pega também a URL gravada depois de abrir o span', () => {
    const atributos = exportarUmSpan({}, { 'http.url': 'https://app.exemplo/x?token=abc' })
    expect(atributos['http.url']).toBe('https://app.exemplo/x')
  })
})

describe('configuração da instrumentação', () => {
  it('nunca liga o registro dos VALORES das consultas', () => {
    expect(CONFIG_PG.enhancedDatabaseReporting).toBe(false)
    expect(CONFIG_PG.requireParentSpan).toBe(true)
  })

  it('não traça a checagem de vida nem os estáticos', () => {
    expect(requisicaoIgnorada('/api/saude')).toBe(true)
    expect(requisicaoIgnorada('/_next/static/chunks/app.js')).toBe(true)
    expect(requisicaoIgnorada('/api/status')).toBe(false)
    expect(requisicaoIgnorada('/sistema')).toBe(false)
    expect(requisicaoIgnorada(undefined)).toBe(false)
  })
})
