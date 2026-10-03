import { z } from 'zod';
import { defineJobContract } from './contract';

/**
 * Drive sync job (docs/09 "Drive connector", ADR 0004). The input references the connection; the
 * worker reads the folder and credential reference through `worker.drive_sync_for_job`. The output
 * is a metadata snapshot of the folder tree, applied by the database in the job's completion
 * transaction. File bytes stay in Drive.
 */

const driveId = z.string().regex(/^[A-Za-z0-9_-]{1,200}$/);

const driveFile = z
  .object({
    drive_file_id: driveId,
    name: z.string().min(1).max(500),
    mime_type: z.string().min(1).max(200),
    revision: z.string().min(1).max(200),
    modified_at: z.iso.datetime({ offset: true }).optional(),
    size_bytes: z.number().int().min(0).optional(),
    md5_checksum: z
      .string()
      .regex(/^[a-f0-9]{32}$/)
      .optional(),
  })
  .strict();

export const driveSyncV1 = defineJobContract({
  type: 'drive.sync',
  schemaVersion: 1,
  description: 'Metadata snapshot of the files under a client Drive folder (no file contents).',
  input: z.object({ connection_id: z.uuid() }).strict(),
  output: z.object({ files: z.array(driveFile).max(5000) }).strict(),
});
