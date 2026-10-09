import { defaultRingGenParams } from '../src/config/game.js';
import {
  CHUNK_SIZE,
  Dir,
  makeRingDef,
  RingGenerator,
  type RingGenParams,
  type RingShape,
} from '../src/maze/index.js';

export function makeRing(
  worldSeed: number,
  ringIndex: number,
  shape: RingShape,
  overrides: Partial<RingGenParams> = {},
  chunkCacheSize?: number,
): RingGenerator {
  const params = { ...defaultRingGenParams(ringIndex), ...overrides };
  const def = makeRingDef({
    worldSeed,
    ringIndex,
    shape,
    params,
    prevParams: ringIndex > 1 ? defaultRingGenParams(ringIndex - 1) : undefined,
  });
  return new RingGenerator(def, chunkCacheSize === undefined ? {} : { chunkCacheSize });
}

export interface RingAnalysis {
  cells: number;
  openEdges: number;
  components: number;
}

/** Count in-ring cells, open internal edges and connected components (union-find). */
export function analyseRing(gen: RingGenerator, withOverlay = true): RingAnalysis {
  const B = gen.def.shape.outerHalf * CHUNK_SIZE;
  const W = 2 * B;
  const parent = new Int32Array(W * W).fill(-1);
  const find = (i: number): number => {
    while (parent[i] !== i) {
      const p = parent[parent[i] as number] as number;
      parent[i] = p;
      i = p;
    }
    return i;
  };
  const idx = (x: number, y: number) => (y + B) * W + (x + B);
  const open = (x: number, y: number, d: Dir) =>
    withOverlay ? gen.isOpen(x, y, d) : gen.isOpenBase(x, y, d);

  let cells = 0;
  for (let y = -B; y < B; y++)
    for (let x = -B; x < B; x++)
      if (gen.cellInRing(x, y)) {
        parent[idx(x, y)] = idx(x, y);
        cells++;
      }

  let openEdges = 0;
  let components = cells;
  for (let y = -B; y < B; y++) {
    for (let x = -B; x < B; x++) {
      if (!gen.cellInRing(x, y)) continue;
      for (const [d, nx, ny] of [
        [Dir.E, x + 1, y],
        [Dir.S, x, y + 1],
      ] as const) {
        if (!gen.cellInRing(nx, ny) || !open(x, y, d)) continue;
        openEdges++;
        const ra = find(idx(x, y));
        const rb = find(idx(nx, ny));
        if (ra !== rb) {
          parent[ra] = rb;
          components--;
        }
      }
    }
  }
  return { cells, openEdges, components };
}

/** BFS over open edges from (sx, sy); returns the set of reached cells as "x,y" keys. */
export function bfsReach(gen: RingGenerator, sx: number, sy: number): Set<string> {
  const seen = new Set<string>([`${sx},${sy}`]);
  const queue: [number, number][] = [[sx, sy]];
  const dx = [0, 1, 0, -1];
  const dy = [-1, 0, 1, 0];
  for (let head = 0; head < queue.length; head++) {
    const [x, y] = queue[head] as [number, number];
    for (let d = 0; d < 4; d++) {
      const nx = x + (dx[d] as number);
      const ny = y + (dy[d] as number);
      if (!gen.cellInRing(nx, ny) || !gen.isOpen(x, y, d as Dir)) continue;
      const k = `${nx},${ny}`;
      if (seen.has(k)) continue;
      seen.add(k);
      queue.push([nx, ny]);
    }
  }
  return seen;
}
