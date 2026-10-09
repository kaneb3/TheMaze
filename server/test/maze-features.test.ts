import fc from 'fast-check';
import { describe, expect, it } from 'vitest';
import {
  chunkBfs,
  CHUNK_SIZE,
  Dir,
  DoorType,
  EdgeDir,
  isTreeDoor,
  treeDistance,
  type RingGenerator,
} from '../src/maze/index.js';
import { makeRing } from './helpers.js';

function chunksOf(gen: RingGenerator): [number, number][] {
  const b = gen.def.shape.outerHalf;
  const out: [number, number][] = [];
  for (let cy = -b; cy < b; cy++)
    for (let cx = -b; cx < b; cx++) if (gen.chunkInRing(cx, cy)) out.push([cx, cy]);
  return out;
}

/** Tally coarse door types over a ring (each owned east/south edge once). */
function coarseStats(gen: RingGenerator) {
  const counts = new Map<DoorType, number>();
  for (const [cx, cy] of chunksOf(gen)) {
    for (const dir of [Dir.E, Dir.S] as const) {
      const t = gen.coarse.side(cx, cy, dir).type;
      counts.set(t, (counts.get(t) ?? 0) + 1);
    }
  }
  return counts;
}

describe('coarse doors', () => {
  it('tree doors = chunks - 1; narrow and plate only on tree doors', () => {
    const gen = makeRing(11, 4, { outerHalf: 6, innerHalf: 2 });
    const stats = coarseStats(gen);
    const tree = [DoorType.Open, DoorType.Narrow, DoorType.Plate].reduce(
      (s, t) => s + (stats.get(t) ?? 0),
      0,
    );
    expect(tree).toBe(gen.coarse.chunkCount - 1);
    expect(gen.coarse.treeEdgeCount).toBe(tree);
    expect(stats.get(DoorType.Narrow) ?? 0).toBeGreaterThan(0);
    expect(stats.get(DoorType.Plate) ?? 0).toBeGreaterThan(0);
    expect(stats.get(DoorType.Lever) ?? 0).toBeGreaterThan(0);
  });

  it('ring 1 has no narrow doors and rings < 3 have no plates (defaults)', () => {
    const r1 = coarseStats(makeRing(11, 1, { outerHalf: 6, innerHalf: 2 }));
    const r2 = coarseStats(makeRing(11, 2, { outerHalf: 6, innerHalf: 2 }));
    expect(r1.get(DoorType.Narrow) ?? 0).toBe(0);
    expect(r1.get(DoorType.Plate) ?? 0).toBe(0);
    expect(r2.get(DoorType.Plate) ?? 0).toBe(0);
  });

  it('every tree door is a single opening on the chunk border; lever doors are closed', () => {
    const gen = makeRing(3, 3, { outerHalf: 4, innerHalf: 1 });
    for (const [cx, cy] of chunksOf(gen)) {
      for (const dir of [Dir.E, Dir.S] as const) {
        const ncx = dir === Dir.E ? cx + 1 : cx;
        const ncy = dir === Dir.E ? cy : cy + 1;
        if (!gen.chunkInRing(ncx, ncy)) continue;
        const { type, door } = gen.coarse.side(cx, cy, dir);
        let open = 0;
        for (let k = 0; k < CHUNK_SIZE; k++) {
          const x = dir === Dir.E ? cx * 32 + 31 : cx * 32 + k;
          const y = dir === Dir.E ? cy * 32 + k : cy * 32 + 31;
          if (gen.isOpen(x, y, dir)) {
            open++;
            expect(k).toBe(door);
          }
        }
        expect(open).toBe(isTreeDoor(type) ? 1 : 0);
      }
    }
  });
});

describe('twin-plate doors', () => {
  it('have a plate pair on both sides, distinct, within plateMaxDistanceCells of the door', () => {
    const gen = makeRing(21, 4, { outerHalf: 6, innerHalf: 2 }, { platePermille: 300 });
    let plateDoors = 0;
    for (const [cx, cy] of chunksOf(gen)) {
      const chunk = gen.chunk(cx, cy);
      for (const dir of [Dir.N, Dir.E, Dir.S, Dir.W] as const) {
        const isPlate = gen.coarse.side(cx, cy, dir).type === DoorType.Plate;
        const pair = chunk.plates.find((p) => p.dir === dir);
        expect(Boolean(pair)).toBe(isPlate);
        if (!pair) continue;
        if (dir === Dir.E || dir === Dir.S) plateDoors++;
        const [p1, p2] = pair.cells;
        expect(p1).not.toBe(p2);
        const { depth } = chunkBfs(chunk.walls, pair.doorCell);
        for (const p of pair.cells) {
          expect(p).not.toBe(pair.doorCell);
          expect(depth[p]).toBeGreaterThan(0);
          expect(depth[p]).toBeLessThanOrEqual(gen.def.params.plateMaxDistanceCells);
        }
      }
    }
    expect(plateDoors).toBeGreaterThan(0);
  });
});

describe('lever walls', () => {
  it('are closed internal walls between cells at least leverMinTreeDistance apart', () => {
    fc.assert(
      fc.property(fc.nat(0xffffffff), (seed) => {
        const gen = makeRing(seed, 2, { outerHalf: 2, innerHalf: 1 }, { leverPermille: 100 });
        let total = 0;
        for (const [cx, cy] of chunksOf(gen)) {
          const chunk = gen.chunk(cx, cy);
          const { parent, depth } = chunkBfs(chunk.walls, 0);
          for (const l of chunk.levers) {
            total++;
            const other = l.edge === EdgeDir.E ? l.cell + 1 : l.cell + CHUNK_SIZE;
            const bit = l.edge === EdgeDir.E ? 1 : 2;
            expect(chunk.walls[l.cell]! & bit).toBe(bit);
            expect(treeDistance(parent, depth, l.cell, other)).toBeGreaterThanOrEqual(
              gen.def.params.leverMinTreeDistance,
            );
          }
        }
        expect(total).toBeGreaterThan(0);
      }),
      { numRuns: 5 },
    );
  });
});

describe('cache spots', () => {
  it('one candidate per chunk with a roll in [0, 1000)', () => {
    const gen = makeRing(8, 1, { outerHalf: 3, innerHalf: 1 });
    const rolls = chunksOf(gen).map(([cx, cy]) => gen.chunk(cx, cy).cache);
    for (const c of rolls) {
      expect(c.cell).toBeGreaterThanOrEqual(0);
      expect(c.cell).toBeLessThan(1024);
      expect(c.roll).toBeGreaterThanOrEqual(0);
      expect(c.roll).toBeLessThan(1000);
    }
    expect(new Set(rolls.map((c) => c.roll)).size).toBeGreaterThan(1);
  });
});
