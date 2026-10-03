/**
 * pt-BR messages for the identity and invitation error contract
 * (tests/acceptance/increment-1/README.md and increment-9/README.md).
 */
const KNOWN = new Map<string, string>([
  ['invalid email', 'Informe um e-mail válido.'],
  ['this person is already a member', 'Esta pessoa já tem acesso.'],
  [
    'client memberships can only hold client-safe capabilities',
    'Membros do cliente só podem ter permissões do portal.',
  ],
  [
    'a client-side member cannot become an internal member of the same workspace',
    'Esta pessoa já é membro de um cliente deste workspace e não pode entrar na equipe interna.',
  ],
  [
    'an internal member cannot hold a client membership in the same workspace',
    'Esta pessoa é da equipe interna e não pode ser membro de um cliente deste workspace.',
  ],
  ['this invitation is no longer pending', 'Este convite já foi usado, revogado ou expirou.'],
  [
    'this invitation is not valid',
    'Este convite não é válido para esta conta: ele pode ter expirado, já ter sido usado ou ser para outro e-mail.',
  ],
  ['role is required', 'Escolha um papel.'],
  ['members cannot change their own membership', 'Você não pode alterar o próprio acesso.'],
  ['unknown user', 'Pessoa não encontrada.'],
  ['no membership to revoke', 'Esta pessoa não tem acesso para revogar.'],
  [
    'the workspace must keep at least one active admin',
    'O workspace precisa manter pelo menos um administrador ativo.',
  ],
  [
    'client name must have 1 to 200 characters',
    'O nome do cliente deve ter de 1 a 200 caracteres.',
  ],
  ['client slug is required', 'Informe o identificador do cliente.'],
  [
    'client slug must be lowercase words separated by hyphens',
    'O identificador deve ter letras minúsculas, números e hífens.',
  ],
]);

export function adminErrorMessage(error: {
  code?: string | undefined;
  message?: string | undefined;
}): string {
  switch (error.code) {
    case '42501':
      return 'Você não tem permissão para esta ação.';
    case 'P0002':
      return 'Item não encontrado ou fora do seu acesso.';
    case '23505':
      return 'Já existe um cliente com este identificador neste workspace.';
    case '22023':
      return (
        (error.message === undefined ? undefined : KNOWN.get(error.message)) ??
        'Esta ação não vale para o estado atual. Atualize a página.'
      );
    default:
      return 'Não foi possível concluir a ação. Tente novamente.';
  }
}
