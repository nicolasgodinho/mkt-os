import { aiModelCheckV1 } from './ai-model-check';
import { driveSyncV1 } from './drive';
import { meetingExtractV1, meetingTranscribeV1 } from './meeting';
import { systemHealthcheckV1 } from './system-healthcheck';

/** Every job contract known to the platform. Add new versions here; never edit a published one. */
export const jobContracts = [
  systemHealthcheckV1,
  aiModelCheckV1,
  meetingExtractV1,
  meetingTranscribeV1,
  driveSyncV1,
] as const;
