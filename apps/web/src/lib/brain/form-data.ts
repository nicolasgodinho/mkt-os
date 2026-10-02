import { z } from 'zod';
import { isSlug } from '../identity/routing';
import {
  ASSIGNABLE_TRUST_LEVELS,
  CONTEXT_KINDS,
  KNOWLEDGE_KINDS,
  RULE_TYPES,
  SOURCE_TYPES,
} from './model';

/**
 * Form parsing for Client Brain actions. Values are only shaped here (types, lengths, empty →
 * null); every business rule is enforced by the database API, which stays the authority.
 */

const optionalText = (max: number) =>
  z
    .string()
    .max(max)
    .transform((value) => value.trim())
    .transform((value) => (value === '' ? null : value))
    .nullable()
    .optional()
    .transform((value) => value ?? null);

const requiredText = (max: number) => z.string().trim().min(1).max(max);
const optionalDate = z
  .string()
  .transform((value) => (value === '' ? null : value))
  .pipe(z.iso.date().nullable())
  .nullable()
  .optional()
  .transform((value) => value ?? null);
const optionalUuid = z
  .string()
  .transform((value) => (value === '' ? null : value))
  .pipe(z.uuid().nullable())
  .nullable()
  .optional()
  .transform((value) => value ?? null);

export const scopeSchema = z.object({
  workspaceSlug: z.string().refine(isSlug),
  clientId: z.uuid(),
});

export const brandProfileForm = scopeSchema.extend({
  business: optionalText(4000),
  brand: optionalText(4000),
  voice: optionalText(4000),
  visualReferences: optionalText(8000).transform((value) =>
    (value ?? '')
      .split(/\r?\n/)
      .map((line) => line.trim())
      .filter((line) => line !== '')
      .slice(0, 50),
  ),
});

export const contextItemForm = scopeSchema.extend({
  kind: z.enum(CONTEXT_KINDS),
  id: optionalUuid,
  name: requiredText(200),
  description: optionalText(2000),
  validFrom: optionalDate,
  validUntil: optionalDate,
});

export const archiveContextItemForm = scopeSchema.extend({
  kind: z.enum(CONTEXT_KINDS),
  id: z.uuid(),
});

export const sourceForm = scopeSchema.extend({
  type: z.enum(SOURCE_TYPES),
  title: requiredText(300),
  trustLevel: z.enum(ASSIGNABLE_TRUST_LEVELS),
  uri: optionalText(2000),
});

export const knowledgeForm = scopeSchema.extend({
  kind: z.enum(KNOWLEDGE_KINDS),
  sourceId: z.uuid(),
  statement: requiredText(2000),
  validFrom: optionalDate,
  validUntil: optionalDate,
  rationale: optionalText(2000),
  decidedAt: optionalDate,
  /** Percent (0–100) in the form; the database stores 0–1. */
  confidence: z
    .string()
    .transform((value) => (value.trim() === '' ? null : Number(value)))
    .pipe(z.number().min(0).max(100).nullable())
    .nullable()
    .optional()
    .transform((value) => (value === null || value === undefined ? null : value / 100)),
});

export const reviewKnowledgeForm = scopeSchema.extend({
  kind: z.enum(KNOWLEDGE_KINDS),
  id: z.uuid(),
  decision: z.enum(['approve', 'reject']),
});

export const ruleForm = scopeSchema.extend({
  sourceId: z.uuid(),
  type: z.enum(RULE_TYPES),
  subject: optionalText(80),
  statement: requiredText(2000),
  channel: optionalText(40),
  priority: z.coerce.number().int().min(0).max(100).default(50),
  effectiveFrom: optionalDate,
  effectiveUntil: optionalDate,
  supersedesRuleId: optionalUuid,
});

export const reviewRuleForm = scopeSchema.extend({
  id: z.uuid(),
  decision: z.enum(['activate', 'reject']),
});

/** FormData → plain object (single values only; files are never accepted here). */
export function formValues(formData: FormData): Record<string, string> {
  const values: Record<string, string> = {};
  for (const [key, value] of formData.entries()) {
    if (typeof value === 'string') values[key] = value;
  }
  return values;
}
