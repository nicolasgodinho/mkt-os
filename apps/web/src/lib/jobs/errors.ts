/** pt-BR messages for the job center error contract (tests/acceptance/increment-3/README.md). */
export function jobErrorMessage(error: { code?: string | undefined }): string {
  switch (error.code) {
    case '42501':
      return 'Você não tem permissão para operar jobs neste workspace.';
    case 'P0002':
      return 'Job não encontrado ou fora do seu acesso.';
    case '22023':
      return 'Esta ação não vale para o estado atual do job. Atualize a página.';
    case '23505':
      return 'Este pedido já foi usado para outro tipo de job. Atualize a página e tente de novo.';
    default:
      return 'Não foi possível concluir a ação. Tente novamente.';
  }
}
