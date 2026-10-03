/** pt-BR messages for the Drive error contract (tests/acceptance/increment-8/README.md). */
const KNOWN = new Map<string, string>([
  ['invalid drive folder id', 'ID de pasta inválido: copie o ID do link da pasta no Drive.'],
  [
    'invalid credential reference',
    'Referência de credencial inválida: use letras minúsculas, números e _.',
  ],
  ['invalid sync interval', 'O intervalo de sincronização deve ficar entre 15 e 1440 minutos.'],
  [
    'this client already has a drive connection',
    'Este cliente já tem uma pasta do Drive conectada.',
  ],
  ['unknown connection status', 'Status de conexão inválido.'],
  ['this drive connection is paused', 'A conexão está pausada: retome-a para sincronizar.'],
  ['removed files cannot be indexed', 'Arquivos removidos do Drive não podem ser indexados.'],
  ['invalid drive sync result', 'O resultado da sincronização foi recusado.'],
  [
    'this folder is already connected to a client',
    'Esta pasta já está conectada a outro cliente: cada pasta alimenta um único cliente.',
  ],
  [
    'drive syncs are retried from the drive page',
    'Sincronizações do Drive são refeitas pela página Drive do cliente.',
  ],
]);

export function driveErrorMessage(error: {
  code?: string | undefined;
  message?: string | undefined;
}): string {
  switch (error.code) {
    case '42501':
      return 'Você não tem permissão para esta ação.';
    case 'P0002':
      return 'Item não encontrado ou fora do seu acesso.';
    case '22023':
      return (
        (error.message === undefined ? undefined : KNOWN.get(error.message)) ??
        'Esta ação não vale para o estado atual. Atualize a página.'
      );
    default:
      return 'Não foi possível concluir a ação. Tente novamente.';
  }
}
