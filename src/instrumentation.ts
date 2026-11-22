import type { Instrumentation } from 'next'

/**
 * Gancho de inicialização do Next (roda uma vez por processo, antes de
 * qualquer requisição). Liga a telemetria só no runtime Node e só quando há
 * um Collector configurado; a verificação de `NEXT_RUNTIME` também deixa o
 * SDK fora do bundle do middleware, que roda no runtime de borda.
 */
export async function register(): Promise<void> {
  if (process.env.NEXT_RUNTIME === 'nodejs' && process.env.OTEL_EXPORTER_OTLP_ENDPOINT) {
    const { iniciarTelemetria } = await import('./lib/telemetria/iniciar')
    iniciarTelemetria()
  }
}

/** Todo erro de requisição que o Next captura vira log e exceção no trace. */
export const onRequestError: Instrumentation.onRequestError = async (erro, requisicao, contexto) => {
  if (process.env.NEXT_RUNTIME !== 'nodejs' || !process.env.OTEL_EXPORTER_OTLP_ENDPOINT) return
  const { registrarErro } = await import('./lib/telemetria/erros')
  registrarErro(erro, requisicao.method, contexto.routePath)
}
