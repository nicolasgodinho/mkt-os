/** pt-BR messages for the calendar error contract (tests/acceptance/increment-7/README.md). */
const KNOWN = new Map<string, string>([
  [
    'only a client-approved revision can be scheduled',
    'Só um conteúdo aprovado pelo cliente (na versão aprovada mais recente) pode ser agendado.',
  ],
  ['publication date must be in the future', 'Escolha uma data de publicação no futuro.'],
  ['invalid channel', 'Canal inválido: use letras minúsculas, números, - ou _.'],
  [
    'this publication can no longer be changed',
    'Esta publicação não pode mais ser alterada. Atualize a página.',
  ],
  ['invalid remote url', 'O link precisa começar com http:// ou https://.'],
  ['invalid calendar range', 'Período do calendário inválido.'],
  [
    'this content can no longer be edited',
    'Este conteúdo foi cancelado ou arquivado e não aceita mais prazos.',
  ],
]);

export function calendarErrorMessage(error: {
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
