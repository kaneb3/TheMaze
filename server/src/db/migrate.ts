// Tiny SQL migration runner: applies server/migrations/NNN_name.sql in order, each in a transaction,
// recording applied ids in schema_migrations. Works with any client via the SqlRunner adapter.

import { readdirSync, readFileSync } from 'node:fs';
import { join } from 'node:path';

export interface SqlRunner {
  /** Execute one or more statements (simple protocol, no parameters). */
  exec(sql: string): Promise<void>;
  query(sql: string): Promise<Record<string, unknown>[]>;
}

export const MIGRATIONS_DIR = join(import.meta.dirname, '../../migrations');

export interface Migration {
  id: string;
  sql: string;
}

export function loadMigrations(dir = MIGRATIONS_DIR): Migration[] {
  return readdirSync(dir)
    .filter((f) => /^\d{3}_[a-z0-9_]+\.sql$/.test(f))
    .sort()
    .map((f) => ({ id: f.replace(/\.sql$/, ''), sql: readFileSync(join(dir, f), 'utf8') }));
}

/** Apply pending migrations. Returns the ids applied in this run. */
export async function migrate(db: SqlRunner, migrations = loadMigrations()): Promise<string[]> {
  await db.exec(`CREATE TABLE IF NOT EXISTS schema_migrations (
    id TEXT PRIMARY KEY,
    applied_at TIMESTAMPTZ NOT NULL DEFAULT now()
  )`);
  const done = new Set((await db.query('SELECT id FROM schema_migrations')).map((r) => String(r.id)));
  const applied: string[] = [];
  for (const m of migrations) {
    if (done.has(m.id)) continue;
    try {
      await db.exec(`BEGIN;\n${m.sql}\n;INSERT INTO schema_migrations (id) VALUES ('${m.id}');\nCOMMIT;`);
    } catch (err) {
      await db.exec('ROLLBACK').catch(() => undefined);
      throw new Error(`migration ${m.id} failed: ${(err as Error).message}`, { cause: err });
    }
    applied.push(m.id);
  }
  return applied;
}
