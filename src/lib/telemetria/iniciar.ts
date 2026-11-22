import { OTLPTraceExporter } from '@opentelemetry/exporter-trace-otlp-proto'
import { NodeSDK } from '@opentelemetry/sdk-node'
import { BatchSpanProcessor } from '@opentelemetry/sdk-trace'
import { instrumentacoes } from './configuracao'
import { ProcessadorDePrivacidade } from './privacidade'

/**
 * Liga o OpenTelemetry no processo Node do Next. Chamado por
 * `src/instrumentation.ts` só quando `OTEL_EXPORTER_OTLP_ENDPOINT` existe: em
 * desenvolvimento, nos testes e na Vercel, nada disto roda.
 *
 * O destino e o formato vêm do ambiente, como na task definition do ECS:
 *   OTEL_EXPORTER_OTLP_ENDPOINT   http://<IP privado do Collector>:4318
 *   OTEL_EXPORTER_OTLP_PROTOCOL   http/protobuf
 *   OTEL_SERVICE_NAME             prumo
 *   OTEL_METRICS_EXPORTER e OTEL_LOGS_EXPORTER   otlp
 *
 * Os traces são montados aqui, e não pelo ambiente, por um motivo: o SDK
 * ignora o exportador do ambiente quando recebe `spanProcessors`, e o
 * processador de privacidade precisa estar na lista.
 */
let sdk: NodeSDK | undefined

export function iniciarTelemetria(): void {
  if (sdk) return

  sdk = new NodeSDK({
    serviceName: process.env.OTEL_SERVICE_NAME || 'prumo',
    spanProcessors: [new ProcessadorDePrivacidade(), new BatchSpanProcessor({ exporter: new OTLPTraceExporter() })],
    instrumentations: instrumentacoes(),
  })
  sdk.start()

  // O ECS manda SIGTERM antes de parar a tarefa: sem isto, os últimos spans
  // do lote ainda não exportado se perderiam a cada deploy.
  process.once('SIGTERM', () => {
    void sdk?.shutdown()
  })
}
