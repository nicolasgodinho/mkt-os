'use client';

import {
  startTransition,
  useActionState,
  useEffect,
  useRef,
  type SyntheticEvent,
  type ReactNode,
} from 'react';
import { Button, cn } from '@jmos/ui';
import { INITIAL_ACTION_STATE, type ActionState } from '@/lib/action-state';

type FormAction = (previous: ActionState, formData: FormData) => Promise<ActionState>;

export interface ActionFormButton {
  label: string;
  /** Sent as `decision=<value>` when this button submits the form. */
  value?: string;
  /** Accessible name when the visible label alone is ambiguous in a list. */
  ariaLabel?: string;
  /** Id of the element that explains why the button is disabled. */
  describedBy?: string;
  variant?: 'primary' | 'secondary' | 'ghost';
  disabled?: boolean;
}

interface ActionFormProps {
  action: FormAction;
  /** Hidden values sent with the form (scope, ids). */
  hidden: Record<string, string>;
  /** Submit buttons. Inline action forms may have none in the current state and only keep
   *  showing the result of the last action (they stay mounted while the item changes status). */
  buttons: readonly ActionFormButton[];
  pendingLabel?: string;
  /** Inline forms are compact action rows (approve, reject, archive) inside lists. */
  variant?: 'form' | 'inline';
  /** Clears the fields after a successful submission (create forms). */
  resetOnSuccess?: boolean;
  className?: string;
  children?: ReactNode;
}

const messageTone: Record<ActionState['status'], string> = {
  idle: '',
  success: 'text-status-success',
  warning: 'text-status-warning',
  error: 'text-status-danger',
};

/**
 * Form bound to a server action, with pending and result feedback. Submission goes
 * through `startTransition` instead of `<form action>` so React does not clear what the user
 * typed when the action returns an error; fields are reset only after a success, on request.
 */
export function ActionForm({
  action,
  hidden,
  buttons,
  pendingLabel = 'Salvando…',
  variant = 'form',
  resetOnSuccess = false,
  className,
  children,
}: ActionFormProps) {
  const [state, formAction, pending] = useActionState(action, INITIAL_ACTION_STATE);
  const formRef = useRef<HTMLFormElement>(null);

  useEffect(() => {
    if (resetOnSuccess && state.status === 'success') formRef.current?.reset();
  }, [state, resetOnSuccess]);

  function onSubmit(event: SyntheticEvent<HTMLFormElement, SubmitEvent>) {
    event.preventDefault();
    const submitter = event.nativeEvent.submitter;
    const formData = new FormData(event.currentTarget, submitter);
    startTransition(() => {
      formAction(formData);
    });
  }

  const inline = variant === 'inline';

  return (
    <form
      ref={formRef}
      onSubmit={onSubmit}
      className={cn(inline ? 'flex flex-col items-start gap-1' : 'flex flex-col gap-3', className)}
    >
      {Object.entries(hidden).map(([name, value]) => (
        <input key={name} type="hidden" name={name} value={value} />
      ))}
      {children}
      <div className={cn('flex flex-wrap items-center', inline ? 'gap-2' : 'gap-3')}>
        {buttons.map((button) => (
          <Button
            key={button.value ?? button.label}
            type="submit"
            name={button.value === undefined ? undefined : 'decision'}
            value={button.value}
            variant={button.variant ?? 'primary'}
            disabled={pending || button.disabled === true}
            aria-label={button.ariaLabel}
            aria-describedby={button.describedBy}
            className={inline ? 'h-7 px-2 text-xs' : undefined}
          >
            {pending && buttons.length === 1 ? pendingLabel : button.label}
          </Button>
        ))}
        {pending && buttons.length !== 1 ? (
          <span className="text-xs text-muted-foreground">{pendingLabel}</span>
        ) : null}
      </div>
      {state.message === null ? null : (
        <p
          role={state.status === 'success' ? 'status' : 'alert'}
          className={cn('text-xs', messageTone[state.status])}
        >
          {state.message}
        </p>
      )}
    </form>
  );
}
