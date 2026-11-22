import { NextResponse } from 'next/server'

export const dynamic = 'force-dynamic'

/**
 * Checagem de vida para o balanceador e para o contêiner.
 *
 * NÃO CONSULTA O BANCO, de propósito, e por dois motivos:
 * 1. O ALB bate aqui a cada poucos segundos em cada tarefa. Se isto tocasse o
 *    Aurora, o health check viraria a maior fonte de consultas do sistema.
 * 2. Com o banco fora, o ALB derrubaria as duas tarefas ao mesmo tempo, e o
 *    site inteiro sumiria em vez de mostrar as páginas que não dependem dele.
 *    Quem mede a saúde do banco é o `/api/status` e a telemetria, não o ALB.
 *
 * O commit vai junto para o teste de fumaça do pipeline conferir que a versão
 * no ar é a que acabou de ser implantada.
 */
export function GET() {
  const commit = process.env.COMMIT_SHA?.slice(0, 7) || 'local'
  return NextResponse.json(
    { ok: true, commit },
    { headers: { 'Cache-Control': 'no-store' } },
  )
}
