// `npm run migrate`: apply migrations to DATABASE_URL.

import postgres from 'postgres';
import { loadEnv } from '../config/env.js';
import { migrate } from './migrate.js';

const env = loadEnv();
const sql = postgres(env.DATABASE_URL, { max: 1, onnotice: () => undefined });

try {
  const applied = await migrate({
    exec: async (text) => {
      await sql.unsafe(text);
    },
    query: async (text) => [...(await sql.unsafe(text))],
  });
  console.log(applied.length ? `applied: ${applied.join(', ')}` : 'database is up to date');
} finally {
  await sql.end();
}
