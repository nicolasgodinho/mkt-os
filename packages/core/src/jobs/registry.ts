import { aiModelCheckV1 } from './ai-model-check';
import { systemHealthcheckV1 } from './system-healthcheck';

/** Every job contract known to the platform. Add new versions here; never edit a published one. */
export const jobContracts = [systemHealthcheckV1, aiModelCheckV1] as const;
