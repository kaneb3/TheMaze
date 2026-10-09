import { readFileSync } from 'node:fs';
import { describe, expect, it } from 'vitest';
import { GEN_VERSION, hash32, Mulberry32 } from '@lantern/server/maze';
import { GOLDEN_PATH, ringOutput, type GoldenFile } from '../src/golden.js';

const golden = JSON.parse(readFileSync(GOLDEN_PATH, 'utf8')) as GoldenFile;

describe('golden generation vectors (shared/golden/gen-v1.json)', () => {
  it('matches the generator version', () => {
    expect(golden.genVersion).toBe(GEN_VERSION);
  });

  it.each(golden.hash32)('hash32($input)', ({ input, output }) => {
    expect(hash32(...input)).toBe(output);
  });

  it.each(golden.mulberry32)('mulberry32($seed)', ({ seed, outputs }) => {
    const r = new Mulberry32(seed);
    expect(outputs.map(() => r.nextU32())).toEqual(outputs);
  });

  it.each(golden.rings.map((r) => [`seed ${r.input.worldSeed} ring ${r.input.ringIndex}`, r] as const))(
    'ring %s',
    (_, { input, output }) => {
      expect(ringOutput(input)).toEqual(output);
    },
  );
});
