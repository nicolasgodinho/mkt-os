import { systemHealthcheckV1 } from './system-healthcheck';

/** Every job contract known to the platform. Add new versions here; never edit a published one. */
export const jobContracts = [systemHealthcheckV1] as const;
