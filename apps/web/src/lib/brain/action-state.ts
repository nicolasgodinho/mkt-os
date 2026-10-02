/** Result of a Client Brain server action, rendered next to the form that submitted it. */
export interface BrainActionState {
  status: 'idle' | 'success' | 'warning' | 'error';
  message: string | null;
}

export const INITIAL_BRAIN_ACTION_STATE: BrainActionState = { status: 'idle', message: null };
