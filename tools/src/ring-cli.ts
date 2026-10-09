// Shared CLI parsing for the debug tools: build a RingGenerator from --seed/--ring/--outer/--inner.

import { parseArgs } from 'node:util';
import { defaultRingGenParams, game } from '@lantern/server/config';
import { makeRingDef, RingGenerator } from '@lantern/server/maze';

export const ringOptions = {
  seed: { type: 'string', default: '1' },
  ring: { type: 'string', default: '3' },
  outer: { type: 'string', default: '4' },
  inner: { type: 'string', default: '2' },
} as const;

export function parseRingArgs<
  T extends Record<string, { type: 'string' | 'boolean'; default?: string | boolean }>,
>(extra: T) {
  const { values } = parseArgs({ options: { ...ringOptions, ...extra }, allowPositionals: false });
  const v = values as Record<string, string | boolean | undefined>;
  const num = (k: string) => {
    const n = Number(v[k]);
    if (!Number.isInteger(n)) throw new Error(`--${k} must be an integer (got ${String(v[k])})`);
    return n;
  };
  const worldSeed = num('seed') >>> 0;
  const ringIndex = num('ring');
  const def = makeRingDef({
    worldSeed,
    ringIndex,
    shape: { outerHalf: num('outer'), innerHalf: num('inner') },
    params: defaultRingGenParams(ringIndex),
    prevParams: ringIndex > 1 ? defaultRingGenParams(ringIndex - 1) : undefined,
    entranceCount: game.entranceCount,
  });
  return { values: v, num, worldSeed, gen: new RingGenerator(def, { chunkCacheSize: game.chunkCacheSize }) };
}
