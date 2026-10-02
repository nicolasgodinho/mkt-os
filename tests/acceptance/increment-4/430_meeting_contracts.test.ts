// PROTECTED ACCEPTANCE TEST (authority: TEST_SPEC). Builders must not edit this file.
// Contract: tests/acceptance/increment-4/README.md — meeting job contracts (docs/08 §5, §7).
import { describe, expect, it } from 'vitest';
import { jobContractKey, jobContracts } from '../../../packages/core/src/index';

function contract(key: string) {
  const found = jobContracts.find((candidate) => jobContractKey(candidate) === key);
  if (found === undefined) throw new Error(`missing job contract ${key}`);
  return found;
}

const MEETING = '20000000-0000-4000-8000-00000000000a';

describe('meeting.extract v1', () => {
  it('references the meeting and transcript revision, never raw content', () => {
    const extract = contract('meeting.extract.v1');
    expect(extract.input.safeParse({ meeting_id: MEETING, transcript_revision: 1 }).success).toBe(
      true,
    );
    expect(extract.input.safeParse({ meeting_id: MEETING }).success).toBe(false);
    expect(
      extract.input.safeParse({ meeting_id: MEETING, transcript_revision: 1, transcript: 'x' })
        .success,
    ).toBe(false);
    expect(extract.input.safeParse({ meeting_id: 'x', transcript_revision: 1 }).success).toBe(
      false,
    );
  });

  it('outputs at most 100 typed proposals; rules carry a rule type', () => {
    const extract = contract('meeting.extract.v1');
    const fact = { kind: 'fact', statement: 'Atende três cidades.', confidence: 0.9 };
    const rule = { ...fact, kind: 'rule', rule_type: 'MUST', subject: 'cta' };
    expect(extract.output.safeParse({ proposals: [fact, rule] }).success).toBe(true);
    expect(
      extract.output.safeParse({
        proposals: [{ ...fact, evidence_quote: 'três cidades', time_ref: '00:03' }],
      }).success,
    ).toBe(true);
    expect(extract.output.safeParse({ proposals: [{ ...fact, kind: 'command' }] }).success).toBe(
      false,
    );
    expect(extract.output.safeParse({ proposals: [{ ...fact, confidence: 2 }] }).success).toBe(
      false,
    );
    expect(extract.output.safeParse({ proposals: [{ ...fact, statement: '' }] }).success).toBe(
      false,
    );
    expect(
      extract.output.safeParse({ proposals: [{ ...rule, rule_type: undefined }] }).success,
    ).toBe(false);
    expect(extract.output.safeParse({ proposals: Array(101).fill(fact) }).success).toBe(false);
    expect(extract.output.safeParse({ proposals: [], activate: true }).success).toBe(false);
  });
});

describe('meeting.transcribe v1', () => {
  it('references the meeting only', () => {
    const transcribe = contract('meeting.transcribe.v1');
    expect(transcribe.input.safeParse({ meeting_id: MEETING }).success).toBe(true);
    expect(transcribe.input.safeParse({ meeting_id: MEETING, path: '/etc/passwd' }).success).toBe(
      false,
    );
  });

  it('outputs the transcript text with optional timed segments', () => {
    const transcribe = contract('meeting.transcribe.v1');
    const valid = {
      text: 'Olá a todos.',
      language: 'pt',
      segments: [{ start_ms: 0, end_ms: 1200, text: 'Olá a todos.' }],
    };
    expect(transcribe.output.safeParse(valid).success).toBe(true);
    expect(transcribe.output.safeParse({ ...valid, text: '' }).success).toBe(false);
    expect(
      transcribe.output.safeParse({ ...valid, segments: [{ start_ms: -1, end_ms: 1, text: 'x' }] })
        .success,
    ).toBe(false);
  });
});
