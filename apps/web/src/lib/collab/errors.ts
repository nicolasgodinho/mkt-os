/** pt-BR messages for the collaboration error contract (tests/acceptance/increment-6/README.md). */
const KNOWN = new Map<string, string>([
  [
    'only an internally approved revision can be sent to the client',
    'Só uma revisão aprovada internamente pode ir para o cliente.',
  ],
  ['this content already has an open approval request', 'Este conteúdo já está com o cliente.'],
  ['unknown approval decision', 'Decisão inválida.'],
  ['comment is too long', 'O comentário é longo demais.'],
  [
    'this approval request is no longer open',
    'Este pedido não está mais aberto: o conteúdo mudou ou já foi decidido. Atualize a página.',
  ],
  ['unknown comment target', 'Não é possível comentar aqui.'],
  ['unknown comment visibility', 'Visibilidade de comentário inválida.'],
  ['comment is required', 'Escreva um comentário.'],
  [
    'this content can no longer be edited',
    'Este conteúdo não pode mais ser editado: crie uma nova versão.',
  ],
]);

export function collabErrorMessage(error: {
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
