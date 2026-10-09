// Regenerate /shared/golden/gen-v1.json. Refuses to overwrite changed vectors unless
// GOLDEN_FORCE=1: after launch, changed vectors mean a broken world, not a stale file.

import { existsSync, mkdirSync, readFileSync, writeFileSync } from 'node:fs';
import { dirname } from 'node:path';
import { isDeepStrictEqual } from 'node:util';
import { computeGolden, GOLDEN_PATH, type GoldenFile } from './golden.js';

const next = computeGolden();
if (existsSync(GOLDEN_PATH) && process.env.GOLDEN_FORCE !== '1') {
  const prev = JSON.parse(readFileSync(GOLDEN_PATH, 'utf8')) as GoldenFile;
  const changed =
    prev.rings.some((r, i) => !isDeepStrictEqual(r, next.rings[i])) ||
    !isDeepStrictEqual(prev.hash32, next.hash32.slice(0, prev.hash32.length)) ||
    !isDeepStrictEqual(prev.mulberry32, next.mulberry32.slice(0, prev.mulberry32.length));
  if (changed) {
    console.error('Existing golden vectors changed. Generation output is not stable!');
    console.error('If this is intentional (pre-launch only), rerun with GOLDEN_FORCE=1.');
    process.exit(1);
  }
}
mkdirSync(dirname(GOLDEN_PATH), { recursive: true });
writeFileSync(GOLDEN_PATH, JSON.stringify(next, null, 2) + '\n');
console.log(`wrote ${GOLDEN_PATH}`);
