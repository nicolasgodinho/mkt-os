import type { InputHTMLAttributes } from 'react';
import { cn } from '../cn';

export interface TextFieldProps extends InputHTMLAttributes<HTMLInputElement> {
  id: string;
  label: string;
}

export function TextField({ id, label, className, ...props }: TextFieldProps) {
  return (
    <div className="flex flex-col gap-1.5">
      <label htmlFor={id} className="text-sm font-medium">
        {label}
      </label>
      <input
        id={id}
        className={cn(
          'h-10 rounded-md border bg-surface px-3 text-sm outline-none focus-visible:border-ring',
          className,
        )}
        {...props}
      />
    </div>
  );
}
