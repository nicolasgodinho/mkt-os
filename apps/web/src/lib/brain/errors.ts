/**
 * Maps Client Brain database errors to pt-BR messages. The error contract is frozen in
 * tests/acceptance/increment-2/README.md: P0002 = not found / no access (never revealing which),
 * 42501 = missing capability, 22023 = invalid argument or ineligible state.
 */

const INVALID_INPUT_MESSAGES = new Map<string, string>(
  Object.entries({
    'untrusted sources cannot become facts or decisions':
      'Fontes externas não confiáveis não podem virar fato ou decisão. Insights podem ser aprovados.',
    'untrusted sources cannot become rules':
      'Regras não podem se basear em fontes externas não confiáveis.',
    'only proposed knowledge can be reviewed':
      'Este item não está mais proposto. Atualize a página para ver o estado atual.',
    'only proposed rules can be activated':
      'Esta regra não está mais proposta. Atualize a página para ver o estado atual.',
    'only proposed or conflicting rules can be rejected':
      'Só regras propostas ou em conflito podem ser rejeitadas. Para retirar uma regra ativa, proponha outra que a substitua.',
    'only active or conflicting rules can be superseded':
      'A regra substituída precisa estar ativa ou em conflito.',
    'hard rules require a subject': 'Regras obrigatórias e proibitivas exigem um assunto.',
    'validity ends before it starts': 'O fim da validade precisa ser depois do início.',
    'offer validity ends before it starts': 'O fim da validade precisa ser depois do início.',
    'invalid channel': 'Canal inválido: use letras minúsculas, números, hífen ou sublinhado.',
    'priority must be between 0 and 100': 'A prioridade vai de 0 a 100.',
    'confidence must be between 0 and 1': 'A confiança vai de 0 a 1.',
    'SYSTEM trust is reserved': 'O nível de confiança Sistema é reservado.',
    'source is required': 'Escolha uma fonte.',
    'type and trust level are required': 'Escolha o tipo e a confiança da fonte.',
    'rule validity has already ended':
      'A validade desta regra já terminou. Proponha uma nova regra com outra data.',
    'unknown context kind': 'Tipo de item inválido.',
    // Meeting intelligence (Increment 4)
    'only proposed items can be reviewed':
      'Esta proposta já foi revisada. Atualize a página para ver o estado atual.',
    'tasks cannot be promoted yet':
      'Tarefas e perguntas ainda não podem virar itens do sistema (chegam com a v0.2). Rejeite ou anote fora.',
    'meeting has no transcript': 'Salve uma transcrição antes de extrair o conhecimento.',
    'meeting has no recording reference':
      'Informe a referência da gravação antes de pedir a transcrição.',
    'a meeting cannot end before it starts': 'O fim da reunião precisa ser depois do início.',
    'invalid recording reference':
      'Referência de gravação inválida: use um caminho relativo dentro da pasta de mídia (sem "..").',
    'invalid participants': 'Participantes inválidos.',
    'title is too long': 'O título é longo demais.',
    'transcript is too long': 'A transcrição é longa demais.',
    'starts_at is required': 'Informe a data e a hora de início.',
    // Raised to the worker only; mapped for completeness of the contract.
    'invalid extraction result': 'O processamento devolveu um resultado inválido.',
    'invalid transcription result': 'O processamento devolveu um resultado inválido.',
    // Content core (Increment 5)
    'an initiative cannot end before it starts':
      'O fim da iniciativa precisa ser depois do início.',
    'kind is required': 'Escolha o tipo.',
    'invalid initiative transition': 'Essa mudança de status não é permitida para a iniciativa.',
    'invalid opportunity type':
      'Tipo de oportunidade inválido: use letras minúsculas, números e _.',
    'unknown review decision': 'Ação inválida.',
    'this opportunity can no longer be reviewed': 'Esta oportunidade já foi tratada.',
    'this opportunity cannot be converted': 'Esta oportunidade não pode mais virar pauta.',
    'a canceled pauta cannot be edited': 'Pautas canceladas não podem ser editadas.',
    'invalid fields': 'Dados inválidos.',
    'unknown pauta field': 'Campo de pauta desconhecido.',
    'invalid field value': 'Valor de campo inválido.',
    'invalid reference list': 'Referências inválidas.',
    'only draft pautas can be marked ready':
      'Só pautas em rascunho podem ser marcadas como prontas.',
    'the pauta does not meet the Definition of Ready':
      'A pauta ainda não cumpre o Definition of Ready: objetivo, público, mensagem ou ângulo e CTA.',
    'invalid content payload': 'Conteúdo inválido.',
    'unknown payload field': 'Campo de conteúdo desconhecido.',
    'content can only execute a ready pauta': 'Conteúdos só podem nascer de uma pauta pronta.',
    'invalid channel or format':
      'Canal ou formato inválido: use letras minúsculas, números, hífen ou sublinhado.',
    'this content can no longer be edited': 'Este conteúdo não pode mais ser editado.',
    'only content in production can be submitted':
      'Só conteúdos em produção podem ser enviados para revisão.',
    'content needs a body before review': 'Escreva o texto antes de enviar para revisão.',
    'this revision is not under internal review':
      'Esta revisão não está mais em revisão interna. Atualize a página.',
    'only the hard rules of this revision can be checked':
      'Só as regras obrigatórias e proibitivas desta revisão podem ser checadas.',
    'note is too long': 'A observação é longa demais.',
    'content has blocking rule checks':
      'Há regras bloqueando a aprovação: confira cada regra e resolva violações e conflitos.',
  }),
);

export interface DatabaseError {
  code?: string | undefined;
  message?: string | undefined;
}

export function brainErrorMessage(error: DatabaseError): string {
  switch (error.code) {
    case '42501':
      return 'Você não tem permissão para esta ação.';
    case 'P0002':
      return 'Item não encontrado ou fora do seu acesso.';
    case '22023': {
      const known =
        error.message === undefined ? undefined : INVALID_INPUT_MESSAGES.get(error.message);
      if (known !== undefined) return known;
      if (error.message?.endsWith(' is required')) {
        return 'Preencha os campos obrigatórios.';
      }
      return 'Dados inválidos. Revise os campos e tente novamente.';
    }
    default:
      return 'Não foi possível concluir a ação. Tente novamente.';
  }
}

/** Errors the user can act on; anything else is unexpected and logged server-side. */
export function isExpectedBrainError(error: DatabaseError): boolean {
  return error.code === '42501' || error.code === 'P0002' || error.code === '22023';
}
