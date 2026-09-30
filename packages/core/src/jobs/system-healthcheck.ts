import { z } from 'zod';
import { defineJobContract } from './contract';

/**
 * Diagnostic round-trip job: proves that a worker can lease, execute and complete a job.
 * It has no domain side effects, which makes it safe to enqueue at any time.
 */
export const systemHealthcheckV1 = defineJobContract({
  type: 'system.healthcheck',
  schemaVersion: 1,
  description: 'Diagnostic lease/execute/complete round-trip. No domain side effects.',
  input: z.object({}).strict(),
  output: z
    .object({
      worker_id: z.string().min(1).max(100),
      worker_version: z.string().min(1).max(50),
      checked_at: z.iso.datetime({ offset: true }),
    })
    .strict(),
});
