import { logs, SeverityNumber, SpanStatusCode, trace } from '@opentelemetry/api'
import { redigirMensagem } from './privacidade'

/**
 * Erro de requisição como log OTLP (Loki) e como exceção no span ativo
 * (Tempo), ligados pelo trace_id. É o único log que a aplicação emite por
 * conta própria, como na Notas da Nuvem: o resto do comportamento está nos
 * traces e nas métricas.
 *
 * Entram a rota (o molde, como `/api/sistema/lancamento`, não a URL), o
 * método, o tipo do erro e a mensagem redigida. Não entram cabeçalhos, cookie,
 * corpo nem query string.
 */
export function registrarErro(erro: unknown, metodo: string, rota: string): void {
  const tipo = erro instanceof Error ? erro.name : typeof erro
  const mensagem = redigirMensagem(erro instanceof Error ? erro.message : String(erro))

  const span = trace.getActiveSpan()
  span?.recordException({ name: tipo, message: mensagem })
  span?.setStatus({ code: SpanStatusCode.ERROR, message: mensagem })

  logs.getLogger('prumo').emit({
    severityNumber: SeverityNumber.ERROR,
    severityText: 'ERROR',
    body: `Erro em ${metodo} ${rota}`,
    attributes: {
      'exception.type': tipo,
      'exception.message': mensagem,
      'http.request.method': metodo,
      'http.route': rota,
    },
  })
}
