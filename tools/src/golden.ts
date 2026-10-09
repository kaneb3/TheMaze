// Golden generation vectors (spec §5.2). The JSON in /shared/golden stores explicit inputs (with
// frozen params, independent of config defaults) and expected output hashes.

import { createHash } from 'node:crypto';
import { join } from 'node:path';
import {
  GEN_VERSION,
  hash32,
  makeRingDef,
  Mulberry32,
  RingGenerator,
  type RingGenParams,
  type RingShape,
} from '@lantern/server/maze';

export const GOLDEN_PATH = join(import.meta.dirname, '../../shared/golden/gen-v1.json');

export interface RingCase {
  worldSeed: number;
  ringIndex: number;
  shape: RingShape;
  params: RingGenParams;
  prevParams?: RingGenParams;
  entranceCount?: number;
}

export interface RingOutput {
  coarse: string;
  gateSlots: number[];
  outerOpenings: number[];
  chunks: Record<string, string>;
  ring: string;
}

export interface GoldenFile {
  genVersion: number;
  hash32: { input: number[]; output: number }[];
  mulberry32: { seed: number; outputs: number[] }[];
  rings: { input: RingCase; output: RingOutput }[];
}

const P = (over: Partial<RingGenParams> = {}): RingGenParams => ({
  newestBiasPermille: 750,
  narrowPermille: 150,
  leverPermille: 15,
  leverMinTreeDistance: 40,
  coarseLeverPermille: 200,
  platePermille: 80,
  plateMaxDistanceCells: 6,
  gateSlotCount: 12,
  gateCount: 5,
  ...over,
});

/** The cases checked into the golden file. Add cases; never edit or remove existing ones. */
export const HASH_CASES: number[][] = [
  [],
  [0],
  [1],
  [-1],
  [1, 2, 3],
  [0xffffffff, 0x80000000, 7],
  [42, 0x52494e47],
];
export const PRNG_SEEDS = [0, 1, 42, 0xdeadbeef];
export const RING_CASES: RingCase[] = [
  {
    worldSeed: 1,
    ringIndex: 1,
    shape: { outerHalf: 3, innerHalf: 1 },
    params: P({ narrowPermille: 0, platePermille: 0 }),
    entranceCount: 4,
  },
  {
    worldSeed: 2026,
    ringIndex: 2,
    shape: { outerHalf: 4, innerHalf: 2 },
    params: P({ platePermille: 0 }),
    prevParams: P(),
  },
  {
    worldSeed: 0xdeadbeef,
    ringIndex: 4,
    shape: { outerHalf: 3, innerHalf: 1 },
    params: P({ newestBiasPermille: 300, platePermille: 250 }),
    prevParams: P(),
  },
];

const sha = (data: string | Uint8Array) => createHash('sha256').update(data).digest('hex');

export function ringOutput(c: RingCase): RingOutput {
  const gen = new RingGenerator(makeRingDef(c));
  const co = gen.coarse;
  const coarse = sha(Buffer.concat([co.eastType, co.southType, co.eastDoor, co.southDoor]));
  const b = c.shape.outerHalf;
  const chunks: Record<string, string> = {};
  const all = createHash('sha256');
  for (let cy = -b; cy < b; cy++) {
    for (let cx = -b; cx < b; cx++) {
      if (!gen.chunkInRing(cx, cy)) continue;
      const ch = gen.chunk(cx, cy);
      const features = JSON.stringify([ch.levers, ch.coarseLevers, ch.borderDoors, ch.plates, ch.cache]);
      const h = sha(Buffer.concat([ch.walls, Buffer.from(features)]));
      all.update(h);
      if ((cx + cy) % 3 === 0) chunks[`${cx},${cy}`] = h;
    }
  }
  return {
    coarse,
    gateSlots: gen.gateSlots.map((g) => g.tFix),
    outerOpenings: gen.outerOpenings.map((o) => o.tFix),
    chunks,
    ring: all.digest('hex'),
  };
}

export function computeGolden(): GoldenFile {
  return {
    genVersion: GEN_VERSION,
    hash32: HASH_CASES.map((input) => ({ input, output: hash32(...input) })),
    mulberry32: PRNG_SEEDS.map((seed) => {
      const r = new Mulberry32(seed);
      return { seed, outputs: Array.from({ length: 8 }, () => r.nextU32()) };
    }),
    rings: RING_CASES.map((input) => ({ input, output: ringOutput(input) })),
  };
}
