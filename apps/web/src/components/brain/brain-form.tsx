'use client';

import { useActionState, useEffect, useRef, type ReactNode } from 'react';
import { Button, cn } from '@jmos/ui';
import { INITIAL_BRAIN_ACTION_STATE, type BrainActionState } from '@/lib/brain/action-state';

type BrainAction = (previous: BrainActionState, formData: FormData) => Promise<BrainActionState>;

interface BrainFormProps {
  action: BrainAction;
  /** Hidden values sent with the form (scope, ids, decision). */
  hidden: Record<string, string>;
  submitLabel: string;
  pendingLabel?: string;
  /** Inline forms are single-button actions (approve, reject, archive) inside lists. */
  variant?: 'form' | 'inline';
  submitVariant?: 'primary' | 'secondary' | 'ghost';
  /** Clears the fields after a successful submission (create forms). */
  resetOnSuccess?: boolean;
  disabled?: boolean;
  className?: string;
  children?: ReactNode;
}

const messageTone: Record<BrainActionState['status'], string> = {
  idle: '',
  success: 'text-status-success',
  warning: 'text-status-warning',
  error: 'text-status-danger',
};

/** Form bound to a Client Brain server action, with pending and result feedback. */
export function BrainForm({
  action,
  hidden,
  submitLabel,
  pendingLabel = 'Salvando…',
  variant = 'form',
  submitVariant = 'primary',
  resetOnSuccess = false,
  disabled = false,
  className,
  children,
}: BrainFormProps) {
  const [state, formAction, pending] = useActionState(action, INITIAL_BRAIN_ACTION_STATE);
  const formRef = useRef<HTMLFormElement>(null);

  useEffect(() => {
    if (resetOnSuccess && state.status === 'success') formRef.current?.reset();
  }, [state, resetOnSuccess]);

  const message =
    state.message === null ? null : (
      <p
        role={state.status === 'success' ? 'status' : 'alert'}
        className={cn('text-xs', messageTone[state.status])}
      >
        {state.message}
      </p>
    );

  return (
    <form
      ref={formRef}
      action={formAction}
      className={cn(
        variant === 'form' ? 'flex flex-col gap-3' : 'inline-flex flex-col items-start gap-1',
        className,
      )}
    >
      {Object.entries(hidden).map(([name, value]) => (
        <input key={name} type="hidden" name={name} value={value} />
      ))}
      {children}
      <div className={cn('flex flex-wrap items-center gap-3', variant === 'inline' && 'gap-1')}>
        <Button
          type="submit"
          variant={submitVariant}
          disabled={pending || disabled}
          className={variant === 'inline' ? 'h-7 px-2 text-xs' : undefined}
        >
          {pending ? pendingLabel : submitLabel}
        </Button>
        {variant === 'form' ? message : null}
      </div>
      {variant === 'inline' ? message : null}
    </form>
  );
}
