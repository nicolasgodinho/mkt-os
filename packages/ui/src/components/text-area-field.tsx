import type { TextareaHTMLAttributes } from 'react';
import { cn } from '../cn';

export interface TextAreaFieldProps extends TextareaHTMLAttributes<HTMLTextAreaElement> {
  id: string;
  label: string;
}

export function TextAreaField({ id, label, className, rows = 3, ...props }: TextAreaFieldProps) {
  return (
    <div className="flex flex-col gap-1.5">
      <label htmlFor={id} className="text-sm font-medium">
        {label}
      </label>
      <textarea
        id={id}
        rows={rows}
        className={cn(
          'rounded-md border bg-surface px-3 py-2 text-sm outline-none focus-visible:border-ring',
          className,
        )}
        {...props}
      />
    </div>
  );
}
