// Deterministic per-chunk features (spec §5.6) computed from the chunk's own maze.

import { hash32, SALT_CACHE, SALT_LEVER, SALT_PLATE } from './hash.js';
import { Mulberry32 } from './prng.js';
import { CHUNK_CELLS, CHUNK_SIZE, Dir, EdgeDir, WALL_E, WALL_S } from './types.js';

const LAST = CHUNK_SIZE - 1;

/** Is the internal edge on side `dir` of local cell c open? Chunk-boundary edges count as closed. */
export function internalOpen(walls: Uint8Array, c: number, dir: Dir): boolean {
  const x = c & LAST;
  const y = c >> 5;
  switch (dir) {
    case Dir.N:
      return y > 0 && ((walls[c - CHUNK_SIZE] as number) & WALL_S) === 0;
    case Dir.E:
      return x < LAST && ((walls[c] as number) & WALL_E) === 0;
    case Dir.S:
      return y < LAST && ((walls[c] as number) & WALL_S) === 0;
    default:
      return x > 0 && ((walls[c - 1] as number) & WALL_E) === 0;
  }
}

const NEIGHBOUR_OFFSET = [-CHUNK_SIZE, 1, CHUNK_SIZE, -1];

/** BFS over the chunk's internal tree from `root`. Returns parent and depth arrays and visit order. */
export function chunkBfs(
  walls: Uint8Array,
  root: number,
  maxDepth = Infinity,
): { parent: Int16Array; depth: Int16Array; order: number[] } {
  const parent = new Int16Array(CHUNK_CELLS).fill(-1);
  const depth = new Int16Array(CHUNK_CELLS).fill(-1);
  const order: number[] = [root];
  depth[root] = 0;
  for (let head = 0; head < order.length; head++) {
    const c = order[head] as number;
    const dc = depth[c] as number;
    if (dc >= maxDepth) continue;
    for (let dir = 0; dir < 4; dir++) {
      if (!internalOpen(walls, c, dir as Dir)) continue;
      const n = c + (NEIGHBOUR_OFFSET[dir] as number);
      if ((depth[n] as number) !== -1) continue;
      depth[n] = dc + 1;
      parent[n] = c;
      order.push(n);
    }
  }
  return { parent, depth, order };
}

export function treeDistance(parent: Int16Array, depth: Int16Array, u: number, v: number): number {
  let dist = 0;
  while ((depth[u] as number) > (depth[v] as number)) {
    u = parent[u] as number;
    dist++;
  }
  while ((depth[v] as number) > (depth[u] as number)) {
    v = parent[v] as number;
    dist++;
  }
  while (u !== v) {
    u = parent[u] as number;
    v = parent[v] as number;
    dist += 2;
  }
  return dist;
}

/** In-chunk lever wall. `side` 0 = lever on the owner cell's side, 1 = on the neighbour's side. */
export interface LeverWall {
  cell: number;
  edge: EdgeDir;
  side: 0 | 1;
}

export function findLeverWalls(
  seed: number,
  cx: number,
  cy: number,
  walls: Uint8Array,
  parent: Int16Array,
  depth: Int16Array,
  leverPermille: number,
  minTreeDistance: number,
): LeverWall[] {
  const out: LeverWall[] = [];
  if (leverPermille <= 0) return out;
  const gx0 = cx * CHUNK_SIZE;
  const gy0 = cy * CHUNK_SIZE;
  for (let c = 0; c < CHUNK_CELLS; c++) {
    const x = c & LAST;
    const y = c >> 5;
    const w = walls[c] as number;
    for (const edge of [EdgeDir.E, EdgeDir.S]) {
      const internal = edge === EdgeDir.E ? x < LAST : y < LAST;
      const closed = (w & (edge === EdgeDir.E ? WALL_E : WALL_S)) !== 0;
      if (!internal || !closed) continue;
      const h = hash32(seed, SALT_LEVER, gx0 + x, gy0 + y, edge);
      if (h % 1000 >= leverPermille) continue;
      const other = edge === EdgeDir.E ? c + 1 : c + CHUNK_SIZE;
      if (treeDistance(parent, depth, c, other) < minTreeDistance) continue;
      out.push({ cell: c, edge, side: (h >>> 31) as 0 | 1 });
    }
  }
  return out;
}

/** A pair of pressure plates on this chunk's side of a twin-plate door. */
export interface PlatePair {
  /** Side of the chunk the door is on. */
  dir: Dir;
  /** Local cell adjacent to the door, on this chunk's side. */
  doorCell: number;
  cells: [number, number];
}

/**
 * Pick two distinct plate cells within `maxDistance` (tree distance inside this chunk) of the door
 * cell. (cxA, cyA, d) identifies the coarse edge; sideFlag 0 = the A (west/north) chunk, 1 = B.
 */
export function placePlates(
  seed: number,
  walls: Uint8Array,
  doorCell: number,
  maxDistance: number,
  cxA: number,
  cyA: number,
  d: EdgeDir,
  sideFlag: 0 | 1,
): [number, number] {
  const { order } = chunkBfs(walls, doorCell, maxDistance);
  const candidates = order.slice(1);
  if (candidates.length < 2) throw new Error('plate placement: fewer than 2 candidate cells');
  const rng = new Mulberry32(hash32(seed, SALT_PLATE, cxA, cyA, d, sideFlag));
  const i1 = rng.randInt(candidates.length);
  let i2 = rng.randInt(candidates.length - 1);
  if (i2 >= i1) i2++;
  return [candidates[i1] as number, candidates[i2] as number];
}

/** One cache candidate per chunk; it exists if roll < cacheDensityPermille at materialisation (§5.9). */
export function cacheSpot(seed: number, cx: number, cy: number): { cell: number; roll: number } {
  return {
    cell: hash32(seed, SALT_CACHE, cx, cy) % CHUNK_CELLS,
    roll: hash32(seed, SALT_CACHE, cx, cy, 1) % 1000,
  };
}
