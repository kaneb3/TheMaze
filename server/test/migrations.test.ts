import { PGlite } from '@electric-sql/pglite';
import { describe, expect, it } from 'vitest';
import { loadMigrations, migrate, type SqlRunner } from '../src/db/migrate.js';

function runner(db: PGlite): SqlRunner {
  return {
    exec: async (sql) => {
      await db.exec(sql);
    },
    query: async (sql) => (await db.query<Record<string, unknown>>(sql)).rows,
  };
}

describe('migrations (in-process Postgres via PGlite)', () => {
  it('apply cleanly, are idempotent, and create the spec tables', async () => {
    const db = new PGlite();
    try {
      const all = loadMigrations().map((m) => m.id);
      expect(all[0]).toBe('001_init');

      expect(await migrate(runner(db))).toEqual(all);
      expect(await migrate(runner(db))).toEqual([]);

      const tables = (
        await db.query<{ tablename: string }>("SELECT tablename FROM pg_tables WHERE schemaname = 'public'")
      ).rows.map((r) => r.tablename);
      for (const t of [
        'worlds',
        'rings',
        'chunk_reveal',
        'camps',
        'camp_ledger',
        'deliveries',
        'opened_walls',
        'gates',
        'pings',
        'lighthouse',
      ]) {
        expect(tables).toContain(t);
      }

      // Constraints that encode spec rules.
      await db.exec(`INSERT INTO worlds (seed, gen_version) VALUES (1, 1)`);
      await expect(
        db.exec(`INSERT INTO rings (world_id, ring_index, seed, gen_version, status, outer_half, inner_half, theme_id, gen_params, live_params)
                 VALUES (1, 1, 5, 1, 'open', 2, 2, 'ring_1', '{}', '{}')`),
      ).rejects.toThrow();
      await db.exec(`INSERT INTO rings (world_id, ring_index, seed, gen_version, status, outer_half, inner_half, theme_id, gen_params, live_params)
                     VALUES (1, 1, 5, 1, 'settled', 3, 1, 'ring_1', '{}', '{}')`);
      await expect(
        db.exec(`INSERT INTO chunk_reveal (ring_id, cx, cy, bits) VALUES (1, 0, 0, '\\x00')`),
      ).rejects.toThrow();
    } finally {
      await db.close();
    }
  });

  it('rolls back a failing migration and reports which one', async () => {
    const db = new PGlite();
    try {
      await expect(
        migrate(runner(db), [
          { id: '001_ok', sql: 'CREATE TABLE a (id INT);' },
          { id: '002_bad', sql: 'CREATE TABLE b (id INT); SELECT * FROM missing_table;' },
        ]),
      ).rejects.toThrow(/002_bad/);
      const ids = (await db.query<{ id: string }>('SELECT id FROM schema_migrations')).rows.map((r) => r.id);
      expect(ids).toEqual(['001_ok']);
      const b = await db.query("SELECT 1 FROM pg_tables WHERE tablename = 'b'");
      expect(b.rows).toHaveLength(0);
    } finally {
      await db.close();
    }
  });
});
