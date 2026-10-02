import { z } from 'zod';
import { defineJobContract } from './contract';

/**
 * Meeting intelligence jobs (docs/03 journey D, docs/08 §7). Inputs are references only; the
 * worker reads the content through job-scoped `worker.*` functions (ADR 0003). Outputs are written
 * by the database in the job's completion transaction, so a redelivery never duplicates them.
 */

const nonBlank = (max: number) => z.string().min(1).max(max).regex(/\S/);

const proposalFields = {
  statement: nonBlank(2000),
  confidence: z.number().min(0).max(1).optional(),
  evidence_quote: z.string().max(1000).optional(),
  time_ref: z.string().max(50).optional(),
};

/** Facts, decisions, insights and tasks/questions: no rule fields. */
const plainProposal = z
  .object({ kind: z.enum(['fact', 'decision', 'insight', 'task']), ...proposalFields })
  .strict();

/** Rules always carry their type; hard rules also need a subject to be accepted later. */
const ruleProposal = z
  .object({
    kind: z.literal('rule'),
    rule_type: z.enum(['MUST', 'MUST_NOT', 'PREFER', 'AVOID']),
    subject: z.string().max(80).optional(),
    ...proposalFields,
  })
  .strict();

export const meetingExtractV1 = defineJobContract({
  type: 'meeting.extract',
  schemaVersion: 1,
  description:
    'Structured extraction of proposed facts, decisions, rules, insights and tasks from one transcript revision.',
  input: z.object({ meeting_id: z.uuid(), transcript_revision: z.number().int().min(1) }).strict(),
  output: z
    .object({ proposals: z.array(z.union([plainProposal, ruleProposal])).max(100) })
    .strict(),
});

export const meetingTranscribeV1 = defineJobContract({
  type: 'meeting.transcribe',
  schemaVersion: 1,
  description: 'Transcription of the meeting recording referenced by the meeting record.',
  input: z.object({ meeting_id: z.uuid() }).strict(),
  output: z
    .object({
      text: nonBlank(500_000),
      language: z.string().max(20).optional(),
      segments: z
        .array(
          z
            .object({
              start_ms: z.number().int().min(0),
              end_ms: z.number().int().min(0),
              text: z.string().max(5000),
            })
            .strict(),
        )
        .max(20_000),
    })
    .strict(),
});
