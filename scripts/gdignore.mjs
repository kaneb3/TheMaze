// Writes .gdignore into node_modules folders so the Godot editor (repo root = res://)
// never scans or imports anything npm installs. Runs as the root postinstall script.
import { existsSync, writeFileSync } from 'node:fs';
import { join } from 'node:path';

const root = join(import.meta.dirname, '..');
const dirs = ['node_modules', 'server/node_modules', 'tools/node_modules'];

for (const dir of dirs) {
  const full = join(root, dir);
  if (existsSync(full)) writeFileSync(join(full, '.gdignore'), '');
}
