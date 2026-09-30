import { jobContractKey, type JobContractRef } from './jobs/contract';

/** Mirrors the `jobs.idempotency_key` length check in `supabase/migrations`. */
export const MAX_IDEMPOTENCY_KEY_LENGTH = 200;

/**
 * Builds a deterministic idempotency key for enqueueing a job (docs/08 §5, docs/11 invariant 6).
 *
 * Derive the parts from the facts that make the unit of work unique, such as meeting id plus
 * source revision. Never use random values or timestamps: an enqueue that is retried or
 * delivered twice must produce the same key so the queue can deduplicate it.
 *
 * Each part is URI-encoded so a delimiter inside a part can never make two different part lists
 * produce the same key.
 */
export function jobIdempotencyKey(
  contract: JobContractRef,
  parts: readonly (string | number)[],
): string {
  if (parts.length === 0) {
    throw new Error('An idempotency key needs at least one part derived from the unit of work.');
  }
  const encoded = parts.map((part, index) => {
    if (typeof part === 'number' && !Number.isFinite(part)) {
      throw new Error(`Idempotency key part #${String(index)} must be a finite number.`);
    }
    const text = String(part);
    if (text.length === 0) {
      throw new Error(`Idempotency key part #${String(index)} must not be empty.`);
    }
    return encodeURIComponent(text);
  });
  const key = [jobContractKey(contract), ...encoded].join(':');
  if (key.length > MAX_IDEMPOTENCY_KEY_LENGTH) {
    throw new RangeError(
      `Idempotency key exceeds ${String(MAX_IDEMPOTENCY_KEY_LENGTH)} characters; use shorter identifiers.`,
    );
  }
  return key;
}
