/** Result of a server action, rendered next to the form that submitted it. */
export interface ActionState {
  status: 'idle' | 'success' | 'warning' | 'error';
  message: string | null;
}

export const INITIAL_ACTION_STATE: ActionState = { status: 'idle', message: null };
