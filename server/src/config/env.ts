// Process environment (not gameplay). Validated once at startup.

import { z } from 'zod';

const EnvSchema = z.object({
  NODE_ENV: z.enum(['development', 'test', 'production']).default('development'),
  DATABASE_URL: z.string().default('postgres://lantern:lantern@localhost:5432/lantern'),
  PORT: z.coerce.number().int().positive().default(7777),
  WORLD_SEED: z.coerce.number().int().min(0).max(0xffffffff).default(1),
  LOG_LEVEL: z.enum(['fatal', 'error', 'warn', 'info', 'debug', 'trace']).default('info'),
});

export type Env = z.infer<typeof EnvSchema>;

export function loadEnv(source: NodeJS.ProcessEnv = process.env): Env {
  return EnvSchema.parse(source);
}
