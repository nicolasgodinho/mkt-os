import type { Metadata } from 'next';
import Link from 'next/link';
import { EmptyState, PageHeader, StatusBadge, TextField } from '@jmos/ui';
import { ActionForm } from '@/components/action-form';
import { resolveBrainContext } from '@/lib/brain/context';
import {
  connectDriveFolder,
  requestDriveSync,
  requestFileReindex,
  setDriveConnectionStatus,
} from '@/lib/drive/actions';
import {
  failureMessage,
  formatSize,
  INDEX_STATUS,
  syncState,
  type SyncState,
} from '@/lib/drive/model';
import { FILES_LIMIT, getConnection, latestSyncJob, listFiles } from '@/lib/drive/queries';
import { getWorkspaceCapabilities } from '@/lib/identity/queries';
import { formatDateTime } from '@/lib/jobs/model';

export const metadata: Metadata = { title: 'Drive' };

function SyncStatus({ state }: { state: SyncState }) {
  switch (state.kind) {
    case 'paused':
      return <StatusBadge tone="neutral">Pausada</StatusBadge>;
    case 'running':
      return <StatusBadge tone="info">Sincronizando agora</StatusBadge>;
    case 'queued':
      return <StatusBadge tone="info">Sincronização na fila</StatusBadge>;
    case 'scheduled':
      return (
        <StatusBadge tone="success">Próxima sincronização {formatDateTime(state.at)}</StatusBadge>
      );
    case 'retrying':
      return <StatusBadge tone="warning">Nova tentativa {formatDateTime(state.at)}</StatusBadge>;
    case 'failed':
      return <StatusBadge tone="danger">Falhou</StatusBadge>;
    case 'idle':
      return <StatusBadge tone="neutral">Sem sincronização agendada</StatusBadge>;
  }
}

/**
 * Client Drive folder (docs/13 Increment 8): the connection, its sync state and the file registry.
 * Internal-only. Bytes stay in Drive; the worker lists the folder and the database keeps metadata.
 */
export default async function DrivePage({
  params,
  searchParams,
}: {
  params: Promise<{ workspaceSlug: string; clientId: string }>;
  searchParams: Promise<Record<string, string | string[] | undefined>>;
}) {
  const { workspaceSlug, clientId } = await params;
  const { workspace, client } = await resolveBrainContext(
    workspaceSlug,
    clientId,
    `/w/${workspaceSlug}/clients/${clientId}/drive`,
  );
  const canManage = (await getWorkspaceCapabilities(workspace.id)).includes('integration.manage');
  const showRemoved = (await searchParams).removidos === '1';
  const connection = await getConnection(client.id);
  const [files, latest] =
    connection === null
      ? [[], null]
      : await Promise.all([listFiles(connection.id, showRemoved), latestSyncJob(connection.id)]);
  const state = connection === null ? null : syncState(connection, latest);
  const scope = { workspaceSlug: workspace.slug, clientId: client.id };
  const base = `/w/${workspace.slug}/clients/${client.id}/drive`;

  return (
    <div className="flex flex-col gap-6">
      <div>
        <nav aria-label="Trilha" className="mb-2 text-xs text-muted-foreground">
          <Link href={`/w/${workspace.slug}/clients`} className="hover:text-foreground">
            Clientes
          </Link>
          <span aria-hidden> / </span>
          <Link
            href={`/w/${workspace.slug}/clients/${client.id}`}
            className="hover:text-foreground"
          >
            {client.name}
          </Link>
        </nav>
        <PageHeader
          title={`Drive: ${client.name}`}
          description="Arquivos da pasta do cliente no Google Drive. Os arquivos ficam no Drive; aqui ficam os metadados e o estado de sincronização."
        />
      </div>

      {connection === null ? (
        <section aria-labelledby="drive-connect" className="rounded-lg border bg-surface p-4">
          <h2 id="drive-connect" className="text-sm font-medium">
            Conectar pasta do Drive
          </h2>
          {canManage ? (
            <ActionForm
              action={connectDriveFolder}
              hidden={scope}
              buttons={[{ label: 'Conectar pasta' }]}
              pendingLabel="Conectando…"
              className="mt-3 max-w-xl"
            >
              <TextField
                id="drive-folder"
                name="folder"
                label="Link ou ID da pasta"
                placeholder="https://drive.google.com/drive/folders/…"
                required
              />
              <TextField
                id="drive-credential"
                name="credentialRef"
                label="Referência da credencial no worker"
                defaultValue="default"
              />
              <TextField
                id="drive-interval"
                name="interval"
                type="number"
                min={15}
                max={1440}
                label="Intervalo de sincronização (minutos)"
                defaultValue="60"
              />
              <p className="text-xs text-muted-foreground">
                Compartilhe a pasta com a conta de serviço do worker (somente leitura). A chave fica
                no worker, nunca no sistema.
              </p>
            </ActionForm>
          ) : (
            <p className="mt-2 text-sm text-muted-foreground">
              Nenhuma pasta conectada. Peça a quem administra integrações para conectar.
            </p>
          )}
        </section>
      ) : (
        <section aria-labelledby="drive-connection" className="rounded-lg border bg-surface p-4">
          <h2 id="drive-connection" className="text-sm font-medium">
            Conexão
          </h2>
          <div className="mt-2 flex flex-wrap items-center gap-2 text-sm">
            {state === null ? null : <SyncStatus state={state} />}
            <span className="text-xs text-muted-foreground">
              Pasta {connection.root_folder_id} · credencial {connection.credential_ref} · a cada{' '}
              {connection.sync_interval_minutes.toString()} min
            </span>
          </div>
          <p className="mt-2 text-sm">
            Última sincronização bem-sucedida:{' '}
            {connection.last_success_at === null
              ? 'nunca'
              : (formatDateTime(connection.last_success_at) ?? '')}
          </p>
          {state !== null && (state.kind === 'failed' || state.kind === 'retrying') ? (
            <p role="status" className="mt-2 rounded-md border border-status-danger p-2 text-sm">
              {failureMessage(state.code)}
              {state.code === null ? null : (
                <span className="ml-1 text-xs text-muted-foreground">({state.code})</span>
              )}
            </p>
          ) : null}
          {canManage ? (
            <div className="mt-3 flex flex-wrap gap-2">
              {connection.status === 'active' ? (
                <ActionForm
                  action={requestDriveSync}
                  hidden={{ ...scope, connectionId: connection.id }}
                  buttons={[{ label: 'Sincronizar agora' }]}
                  pendingLabel="Solicitando…"
                  variant="inline"
                />
              ) : null}
              <ActionForm
                action={setDriveConnectionStatus}
                hidden={{ ...scope, connectionId: connection.id }}
                buttons={[
                  connection.status === 'active'
                    ? { label: 'Pausar', value: 'paused', variant: 'secondary' }
                    : { label: 'Retomar', value: 'active' },
                ]}
                variant="inline"
              />
            </div>
          ) : null}
        </section>
      )}

      {connection === null ? null : (
        <section aria-labelledby="drive-files">
          <div className="mb-2 flex flex-wrap items-center justify-between gap-2">
            <h2 id="drive-files" className="text-sm font-medium">
              Arquivos
            </h2>
            <Link
              href={showRemoved ? base : `${base}?removidos=1`}
              className="text-xs text-primary"
            >
              {showRemoved ? 'Ocultar removidos' : 'Mostrar removidos'}
            </Link>
          </div>
          {files.length === 0 ? (
            <EmptyState
              title="Nenhum arquivo registrado"
              description="Os arquivos aparecem depois da primeira sincronização."
            />
          ) : (
            <ul className="flex flex-col gap-2" aria-label="Arquivos do Drive">
              {files.map((file) => (
                <li key={file.id} className="rounded-lg border bg-surface p-3 text-sm">
                  <div className="flex flex-wrap items-center gap-2">
                    <span className="font-medium break-all">{file.name}</span>
                    {file.sync_status === 'removed' ? (
                      <StatusBadge tone="neutral">Removido do Drive</StatusBadge>
                    ) : null}
                    <StatusBadge tone={INDEX_STATUS[file.index_status].tone}>
                      {INDEX_STATUS[file.index_status].label}
                    </StatusBadge>
                  </div>
                  <p className="mt-1 text-xs text-muted-foreground">
                    {file.mime_type}
                    {formatSize(file.size_bytes) === null
                      ? ''
                      : ` · ${formatSize(file.size_bytes) ?? ''}`}
                    {file.modified_at
                      ? ` · alterado em ${formatDateTime(file.modified_at) ?? ''}`
                      : ''}
                  </p>
                  {canManage &&
                  file.sync_status === 'synced' &&
                  file.index_status !== 'indexing' ? (
                    <ActionForm
                      action={requestFileReindex}
                      hidden={{ ...scope, fileId: file.id }}
                      buttons={[
                        {
                          label: 'Indexar de novo',
                          ariaLabel: `Indexar de novo ${file.name}`,
                          variant: 'secondary',
                        },
                      ]}
                      variant="inline"
                      className="mt-2"
                    />
                  ) : null}
                </li>
              ))}
            </ul>
          )}
          {files.length >= FILES_LIMIT ? (
            <p className="mt-2 text-xs text-muted-foreground">
              Mostrando os primeiros {FILES_LIMIT.toString()} arquivos.
            </p>
          ) : null}
        </section>
      )}
    </div>
  );
}
