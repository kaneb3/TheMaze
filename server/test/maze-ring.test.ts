import fc from 'fast-check';
import { describe, expect, it } from 'vitest';
import {
  boundaryEdgeCount,
  CHUNK_SIZE,
  DIR_DX,
  DIR_DY,
  Dir,
  innerBoundaryEdge,
  outerBoundaryEdge,
} from '../src/maze/index.js';
import { analyseRing, bfsReach, makeRing } from './helpers.js';

const smallShape = fc
  .record({ b: fc.integer({ min: 2, max: 4 }), a: fc.integer({ min: 1, max: 3 }) })
  .filter(({ a, b }) => a < b)
  .map(({ a, b }) => ({ outerHalf: b, innerHalf: a }));

describe('ring generation: perfect-maze property (base layout)', () => {
  it('cells - 1 = open edges, single component, for random small rings', () => {
    fc.assert(
      fc.property(
        fc.nat(0xffffffff),
        fc.integer({ min: 1, max: 5 }),
        smallShape,
        (seed, ringIndex, shape) => {
          const gen = makeRing(seed, ringIndex, shape);
          const { cells, openEdges, components } = analyseRing(gen, false);
          expect(cells).toBe(4 * (shape.outerHalf ** 2 - shape.innerHalf ** 2) * CHUNK_SIZE * CHUNK_SIZE);
          expect(openEdges).toBe(cells - 1);
          expect(components).toBe(1);
        },
      ),
      { numRuns: 12 },
    );
  });

  it('BFS from an entrance reaches every cell and every gate (ring 1)', () => {
    const gen = makeRing(42, 1, { outerHalf: 3, innerHalf: 1 });
    expect(gen.outerOpenings.map((o) => o.kind)).toEqual(['entrance', 'entrance', 'entrance', 'entrance']);
    const entrance = gen.outerOpenings[0]!.edge;
    const reached = bfsReach(gen, entrance.x, entrance.y);
    expect(reached.size).toBe(analyseRing(gen).cells);
    for (const g of gen.gateSlots) expect(reached.has(`${g.edge.x},${g.edge.y}`)).toBe(true);
  });

  it('BFS from an arrival reaches every cell (ring 2)', () => {
    const gen = makeRing(42, 2, { outerHalf: 4, innerHalf: 2 });
    expect(gen.outerOpenings.every((o) => o.kind === 'arrival')).toBe(true);
    const arrival = gen.outerOpenings[0]!.edge;
    expect(bfsReach(gen, arrival.x, arrival.y).size).toBe(analyseRing(gen).cells);
  });
});

describe('ring boundaries', () => {
  it('are closed everywhere except entrances / arrivals / active gates', () => {
    fc.assert(
      fc.property(
        fc.nat(0xffffffff),
        fc.integer({ min: 1, max: 4 }),
        smallShape,
        (seed, ringIndex, shape) => {
          const gen = makeRing(seed, ringIndex, shape);
          const expected = new Set(gen.baseOpenings);
          let openCount = 0;
          for (let e = 0; e < boundaryEdgeCount(shape.outerHalf); e++) {
            const be = outerBoundaryEdge(shape.outerHalf, e);
            const open = gen.isOpen(be.x, be.y, be.dir);
            expect(open).toBe(expected.has(be.key));
            if (open) openCount++;
          }
          for (let e = 0; e < boundaryEdgeCount(shape.innerHalf); e++) {
            const be = innerBoundaryEdge(shape.innerHalf, e);
            const open = gen.isOpen(be.x, be.y, be.dir);
            expect(open).toBe(expected.has(be.key));
            if (open) openCount++;
          }
          expect(openCount).toBe(expected.size);
          expect(expected.size).toBe(gen.outerOpenings.length + gen.def.params.gateCount);
        },
      ),
      { numRuns: 15 },
    );
  });

  it('the edge query is symmetric (seen from either cell)', () => {
    const gen = makeRing(7, 3, { outerHalf: 3, innerHalf: 1 });
    const B = 3 * CHUNK_SIZE;
    for (let y = -B - 1; y <= B; y += 3) {
      for (let x = -B - 1; x <= B; x++) {
        for (const d of [Dir.E, Dir.S] as const) {
          const nx = x + DIR_DX[d]!;
          const ny = y + DIR_DY[d]!;
          const back = d === Dir.E ? Dir.W : Dir.N;
          expect(gen.isOpen(nx, ny, back)).toBe(gen.isOpen(x, y, d));
        }
      }
    }
  });
});

describe('determinism', () => {
  it('chunks are identical regardless of generation order and cache size', () => {
    const shape = { outerHalf: 3, innerHalf: 1 };
    const a = makeRing(99, 3, shape);
    const b = makeRing(99, 3, shape, {}, 1);
    const coords: [number, number][] = [];
    for (let cy = -3; cy < 3; cy++)
      for (let cx = -3; cx < 3; cx++) if (a.chunkInRing(cx, cy)) coords.push([cx, cy]);
    const fromA = coords.map(([cx, cy]) => a.chunk(cx, cy));
    const fromB = [...coords]
      .reverse()
      .map(([cx, cy]) => b.chunk(cx, cy))
      .reverse();
    expect(fromB).toEqual(fromA);
  });

  it('different seeds give different mazes', () => {
    const shape = { outerHalf: 2, innerHalf: 1 };
    expect(makeRing(1, 1, shape).chunk(-2, -2).walls).not.toEqual(makeRing(2, 1, shape).chunk(-2, -2).walls);
  });
});

describe('opening overlay', () => {
  it('opening one lever wall adds exactly one loop and keeps the ring connected', () => {
    const gen = makeRing(5, 2, { outerHalf: 3, innerHalf: 1 });
    let lever: { x: number; y: number; d: Dir } | undefined;
    for (let cy = -3; cy < 3 && !lever; cy++) {
      for (let cx = -3; cx < 3 && !lever; cx++) {
        if (!gen.chunkInRing(cx, cy)) continue;
        const l = gen.chunk(cx, cy).levers[0];
        if (l)
          lever = { x: cx * 32 + (l.cell & 31), y: cy * 32 + (l.cell >> 5), d: l.edge === 0 ? Dir.E : Dir.S };
      }
    }
    expect(lever).toBeDefined();
    const before = analyseRing(gen);
    expect(gen.isOpen(lever!.x, lever!.y, lever!.d)).toBe(false);
    gen.openEdge(lever!.x, lever!.y, lever!.d);
    expect(gen.isOpen(lever!.x, lever!.y, lever!.d)).toBe(true);
    expect(gen.isOpenBase(lever!.x, lever!.y, lever!.d)).toBe(false);
    const after = analyseRing(gen);
    expect(after.openEdges).toBe(before.openEdges + 1);
    expect(after.components).toBe(1);
  });

  it('refuses edges that do not touch the ring', () => {
    const gen = makeRing(5, 2, { outerHalf: 3, innerHalf: 1 });
    expect(() => gen.openEdge(0, 0, Dir.E)).toThrow();
  });
});
