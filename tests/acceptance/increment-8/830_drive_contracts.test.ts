// PROTECTED ACCEPTANCE TEST (authority: TEST_SPEC). Builders must not edit this file.
// Contract: tests/acceptance/increment-8/README.md — the drive.sync job contract (docs/08 §5).
import { describe, expect, it } from 'vitest';
import { jobContractKey, jobContracts } from '../../../packages/core/src/index';

function contract(key: string) {
  const found = jobContracts.find((candidate) => jobContractKey(candidate) === key);
  if (found === undefined) throw new Error(`missing job contract ${key}`);
  return found;
}

const CONNECTION = '20000000-0000-4000-8000-00000000000a';
const FILE = {
  drive_file_id: '1AbCdEfGhIjKlMnOpQrStUvWxYz',
  name: 'Briefing.docx',
  mime_type: 'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
  revision: '0B1-rev-42',
};

describe('drive.sync v1', () => {
  it('references the connection only: no folder, credential or secret in the job', () => {
    const sync = contract('drive.sync.v1');
    expect(sync.input.safeParse({ connection_id: CONNECTION }).success).toBe(true);
    expect(sync.input.safeParse({}).success).toBe(false);
    expect(sync.input.safeParse({ connection_id: 'x' }).success).toBe(false);
    expect(
      sync.input.safeParse({ connection_id: CONNECTION, credential_ref: 'default' }).success,
    ).toBe(false);
    expect(
      sync.input.safeParse({ connection_id: CONNECTION, access_token: 'ya29.secret' }).success,
    ).toBe(false);
  });

  it('outputs a metadata snapshot of at most 5000 files, never file contents', () => {
    const sync = contract('drive.sync.v1');
    expect(sync.output.safeParse({ files: [] }).success).toBe(true);
    expect(
      sync.output.safeParse({
        files: [
          FILE,
          {
            ...FILE,
            drive_file_id: 'other-file_2',
            size_bytes: 2048,
            md5_checksum: '0123456789abcdef0123456789abcdef',
            modified_at: '2026-10-02T12:00:00.000Z',
          },
        ],
      }).success,
    ).toBe(true);
    expect(sync.output.safeParse({ files: [{ ...FILE, drive_file_id: '../x' }] }).success).toBe(
      false,
    );
    expect(sync.output.safeParse({ files: [{ ...FILE, name: '' }] }).success).toBe(false);
    expect(sync.output.safeParse({ files: [{ ...FILE, content: 'bytes' }] }).success).toBe(false);
    expect(sync.output.safeParse({ files: [{ ...FILE, size_bytes: -1 }] }).success).toBe(false);
    expect(sync.output.safeParse({ files: Array(5001).fill(FILE) }).success).toBe(false);
    expect(sync.output.safeParse({ files: [], cursor: 'x' }).success).toBe(false);
  });
});
