import type { z } from 'zod';

/**
 * A versioned background-job payload contract (docs/08 §5 and §7).
 *
 * `type` + `schemaVersion` identify the contract: `meeting.extract` v1 is `meeting.extract.v1`.
 * Input carries references to domain records, never secrets or large blobs.
 *
 * The zod definitions are the single source of truth. The Python AI Worker validates
 * against the JSON Schema generated from them (`pnpm contracts:generate`), so the contract
 * is never hand-duplicated across languages.
 */
export interface JobContract<I extends z.ZodType = z.ZodType, O extends z.ZodType = z.ZodType> {
  readonly type: string;
  readonly schemaVersion: number;
  readonly description: string;
  readonly input: I;
  readonly output: O;
}

export type JobContractRef = Pick<JobContract, 'type' | 'schemaVersion'>;

export function defineJobContract<I extends z.ZodType, O extends z.ZodType>(
  contract: JobContract<I, O>,
): JobContract<I, O> {
  return contract;
}

/** Stable identifier used by the queue to route jobs, e.g. `system.healthcheck.v1`. */
export function jobContractKey(contract: JobContractRef): string {
  return `${contract.type}.v${String(contract.schemaVersion)}`;
}
