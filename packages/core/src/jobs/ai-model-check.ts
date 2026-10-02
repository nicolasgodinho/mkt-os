import { z } from 'zod';
import { defineJobContract } from './contract';

/**
 * Model adapter round-trip (docs/08 §3–§4): the worker asks the model behind a task profile a
 * fixed question and reports which model answered and how fast. The input is empty on purpose:
 * the prompt belongs to the pipeline, so no user text reaches the model through this job.
 */
export const aiModelCheckV1 = defineJobContract({
  type: 'ai.model_check',
  schemaVersion: 1,
  description: 'Fixed-prompt check of the model behind a task profile. No domain side effects.',
  input: z.object({}).strict(),
  output: z
    .object({
      model_profile: z.string().min(1).max(100),
      model: z.string().min(1).max(200),
      latency_ms: z.number().int().min(0),
      ok: z.boolean(),
    })
    .strict(),
});
