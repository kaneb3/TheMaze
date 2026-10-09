import fc from 'fast-check';
import { describe, expect, it } from 'vitest';
import { defaultRingGenParams } from '../src/config/game.js';
import {
  activeSlotIndices,
  arrivalOpenings,
  boundaryEdgeCount,
  CHUNK_SIZE,
  cellInRing,
  DIR_DX,
  DIR_DY,
  Dir,
  edgeIndexForT,
  edgeKeyDir,
  entranceTFix,
  gateSlotTFix,
  innerBoundaryEdge,
  outerBoundaryEdge,
  ringSeed,
  TWO_POW_32,
  type RingShape,
} from '../src/maze/index.js';
import { makeRing } from './helpers.js';

/** Brute force: all edges between an in-ring cell and an out-of-ring cell, split inner / outer. */
function bruteBoundary(shape: RingShape): { inner: Set<number>; outer: Set<number> } {
  const B = shape.outerHalf * CHUNK_SIZE;
  const A = shape.innerHalf * CHUNK_SIZE;
  const inner = new Set<number>();
  const outer = new Set<number>();
  for (let y = -B; y < B; y++) {
    for (let x = -B; x < B; x++) {
      if (!cellInRing(shape, x, y)) continue;
      for (const d of [Dir.N, Dir.E, Dir.S, Dir.W]) {
        const nx = x + DIR_DX[d]!;
        const ny = y + DIR_DY[d]!;
        if (cellInRing(shape, nx, ny)) continue;
        const inHole = nx >= -A && nx < A && ny >= -A && ny < A;
        (inHole ? inner : outer).add(edgeKeyDir(x, y, d));
      }
    }
  }
  return { inner, outer };
}

describe('boundary edge walk', () => {
  it.each([
    { outerHalf: 2, innerHalf: 1 },
    { outerHalf: 4, innerHalf: 1 },
    { outerHalf: 5, innerHalf: 3 },
  ])('covers each boundary edge exactly once (%o)', (shape) => {
    const brute = bruteBoundary(shape);
    const inner = new Set<number>();
    for (let e = 0; e < boundaryEdgeCount(shape.innerHalf); e++) {
      const be = innerBoundaryEdge(shape.innerHalf, e);
      expect(cellInRing(shape, be.x, be.y)).toBe(true);
      inner.add(be.key);
    }
    const outer = new Set<number>();
    for (let e = 0; e < boundaryEdgeCount(shape.outerHalf); e++) {
      const be = outerBoundaryEdge(shape.outerHalf, e);
      expect(cellInRing(shape, be.x, be.y)).toBe(true);
      outer.add(be.key);
    }
    expect(inner.size).toBe(boundaryEdgeCount(shape.innerHalf));
    expect(outer.size).toBe(boundaryEdgeCount(shape.outerHalf));
    expect(inner).toEqual(brute.inner);
    expect(outer).toEqual(brute.outer);
  });

  it('walks clockwise from the top-left corner', () => {
    expect(outerBoundaryEdge(2, 0)).toMatchObject({ x: -64, y: -64, dir: Dir.N });
    expect(outerBoundaryEdge(2, 128)).toMatchObject({ x: 63, y: -64, dir: Dir.E });
    expect(outerBoundaryEdge(2, 256)).toMatchObject({ x: 63, y: 63, dir: Dir.S });
    expect(outerBoundaryEdge(2, 384)).toMatchObject({ x: -64, y: 63, dir: Dir.W });
    expect(innerBoundaryEdge(1, 0)).toMatchObject({ x: -32, y: -33, dir: Dir.S });
    expect(innerBoundaryEdge(1, 64)).toMatchObject({ x: 32, y: -32, dir: Dir.W });
  });
});

describe('fixed-point t', () => {
  it('maps tFix into [0, count) and preserves order', () => {
    fc.assert(
      fc.property(
        fc.nat(0xffffffff),
        fc.nat(0xffffffff),
        fc.integer({ min: 1, max: 100_000 }),
        (t1, t2, n) => {
          const e1 = edgeIndexForT(t1, n);
          const e2 = edgeIndexForT(t2, n);
          expect(e1).toBeGreaterThanOrEqual(0);
          expect(e1).toBeLessThan(n);
          if (t1 <= t2) expect(e1).toBeLessThanOrEqual(e2);
        },
      ),
    );
  });

  it('round-trips between two rings of different sizes (same fraction within one edge)', () => {
    fc.assert(
      fc.property(
        fc.nat(0xffffffff),
        fc.integer({ min: 1, max: 200 }),
        fc.integer({ min: 1, max: 200 }),
        (t, h1, h2) => {
          const n1 = boundaryEdgeCount(h1);
          const n2 = boundaryEdgeCount(h2);
          const f1 = edgeIndexForT(t, n1) / n1;
          const f2 = edgeIndexForT(t, n2) / n2;
          const tf = t / TWO_POW_32;
          expect(tf - f1).toBeGreaterThanOrEqual(0);
          expect(tf - f1).toBeLessThan(1 / n1);
          expect(Math.abs(f1 - f2)).toBeLessThan(1 / n1 + 1 / n2);
        },
      ),
    );
  });

  it('entrances sit at the N/E/S/W midpoints', () => {
    const t = entranceTFix(4);
    expect(t).toEqual([0.125, 0.375, 0.625, 0.875].map((f) => f * TWO_POW_32));
    const n = boundaryEdgeCount(3);
    const mid = (e: number) => outerBoundaryEdge(3, edgeIndexForT(t[e]!, n));
    expect(mid(0)).toMatchObject({ x: 0, dir: Dir.N });
    expect(mid(1)).toMatchObject({ y: 0, dir: Dir.E });
    expect(mid(2)).toMatchObject({ x: -1, dir: Dir.S });
    expect(mid(3)).toMatchObject({ y: -1, dir: Dir.W });
  });
});

describe('gate slots', () => {
  it('slots are increasing, each within its jitter window', () => {
    fc.assert(
      fc.property(fc.nat(0xffffffff), fc.integer({ min: 1, max: 24 }), (seed, n) => {
        const t = gateSlotTFix(seed, n);
        expect(t).toHaveLength(n);
        t.forEach((v, i) => {
          const f = (v / TWO_POW_32) * n - i;
          expect(f).toBeGreaterThanOrEqual(0.1 - 1e-6);
          expect(f).toBeLessThan(0.9);
        });
      }),
    );
  });

  it('active slots are spread evenly', () => {
    expect(activeSlotIndices(12, 5)).toEqual([0, 2, 4, 7, 9]);
    expect(activeSlotIndices(12, 12)).toEqual([0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11]);
    expect(() => activeSlotIndices(4, 5)).toThrow();
  });

  it("ring k+1's arrivals match ring k's active gates", () => {
    const params = defaultRingGenParams(2);
    const ring2 = makeRing(1234, 2, { outerHalf: 6, innerHalf: 3 });
    const ring3 = makeRing(1234, 3, { outerHalf: 3, innerHalf: 1 });
    const active = ring2.gateSlots.filter((g) => g.active).map((g) => g.tFix);
    expect(ring3.outerOpenings.map((o) => o.tFix)).toEqual(active);
    expect(arrivalOpenings(ringSeed(1234, 2), params).map((o) => o.tFix)).toEqual(active);
    expect(ring2.gateSlots).toHaveLength(12);
    expect(ring2.gateSlots.filter((g) => g.active)).toHaveLength(5);
  });
});
