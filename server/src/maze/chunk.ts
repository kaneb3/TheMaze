// Per-chunk perfect maze (spec §5.5): Growing Tree over 32×32 cells, plus the chunk's owned
// boundary edges (doors from the coarse maze, ring-boundary openings) and deterministic features.

import { CoarseLayout, DoorType, isTreeDoor } from './coarse.js';
import {
  cacheSpot,
  chunkBfs,
  findLeverWalls,
  placePlates,
  type LeverWall,
  type PlatePair,
} from './features.js';
import { chunkInRing, edgeKey } from './geometry.js';
import { hash32, SALT_CHUNK, SALT_COARSE_LEVER } from './hash.js';
import { Mulberry32 } from './prng.js';
import { CHUNK_CELLS, CHUNK_SIZE, Dir, EdgeDir, WALL_E, WALL_S, type RingDef } from './types.js';

const LAST = CHUNK_SIZE - 1;

/** Closed coarse lever door on an edge this chunk owns (its east or south border). */
export interface CoarseLeverDoor {
  cell: number;
  edge: EdgeDir;
  /** 0 = lever on this chunk's side, 1 = on the neighbour's side. */
  side: 0 | 1;
}

/** Owned-edge feature on this chunk's east/south border that isn't a plain open door. */
export interface BorderDoor {
  cell: number;
  edge: EdgeDir;
  type: DoorType;
}

export interface ChunkData {
  cx: number;
  cy: number;
  /** 1024 cells × (bit0 = east wall, bit1 = south wall), 256 bytes when bit-packed. */
  walls: Uint8Array;
  levers: LeverWall[];
  coarseLevers: CoarseLeverDoor[];
  /** Narrow / plate tree doors on the east and south borders. */
  borderDoors: BorderDoor[];
  /** Plate pairs on this chunk's side of any adjacent twin-plate door (all four sides). */
  plates: PlatePair[];
  cache: { cell: number; roll: number };
}

export interface ChunkContext {
  def: RingDef;
  coarse: CoarseLayout;
  /** Base ring-boundary openings (entrances, arrivals, active gates) as owned-edge keys. */
  baseOpenings: ReadonlySet<number>;
}

/** Growing Tree carve of the chunk interior. Boundary edges stay walls. */
export function carveChunk(seed: number, newestBiasPermille: number): Uint8Array {
  const walls = new Uint8Array(CHUNK_CELLS).fill(WALL_E | WALL_S);
  const visited = new Uint8Array(CHUNK_CELLS);
  const active = new Int16Array(CHUNK_CELLS);
  const cand = new Int8Array(4);
  const rng = new Mulberry32(seed);

  let len = 0;
  const start = rng.randInt(CHUNK_CELLS);
  visited[start] = 1;
  active[len++] = start;

  while (len > 0) {
    const i = rng.chance(newestBiasPermille) ? len - 1 : rng.randInt(len);
    const c = active[i] as number;
    const x = c & LAST;
    const y = c >> 5;

    let n = 0;
    if (y > 0 && !visited[c - CHUNK_SIZE]) cand[n++] = Dir.N;
    if (x < LAST && !visited[c + 1]) cand[n++] = Dir.E;
    if (y < LAST && !visited[c + CHUNK_SIZE]) cand[n++] = Dir.S;
    if (x > 0 && !visited[c - 1]) cand[n++] = Dir.W;

    if (n === 0) {
      // Order-preserving removal so "newest" keeps its meaning.
      active.copyWithin(i, i + 1, len);
      len--;
      continue;
    }

    let next: number;
    switch (cand[rng.randInt(n)]) {
      case Dir.N:
        next = c - CHUNK_SIZE;
        walls[next] = (walls[next] as number) & ~WALL_S;
        break;
      case Dir.E:
        next = c + 1;
        walls[c] = (walls[c] as number) & ~WALL_E;
        break;
      case Dir.S:
        next = c + CHUNK_SIZE;
        walls[c] = (walls[c] as number) & ~WALL_S;
        break;
      default:
        next = c - 1;
        walls[next] = (walls[next] as number) & ~WALL_E;
    }
    visited[next] = 1;
    active[len++] = next;
  }
  return walls;
}

export function generateChunk(ctx: ChunkContext, cx: number, cy: number): ChunkData {
  const { def, coarse, baseOpenings } = ctx;
  const { seed, params } = def;
  const walls = carveChunk(hash32(seed, SALT_CHUNK, cx, cy), params.newestBiasPermille);
  const gx0 = cx * CHUNK_SIZE;
  const gy0 = cy * CHUNK_SIZE;

  const coarseLevers: CoarseLeverDoor[] = [];
  const borderDoors: BorderDoor[] = [];

  // Owned borders: east (x = 31) and south (y = 31).
  for (const edge of [EdgeDir.E, EdgeDir.S]) {
    const east = edge === EdgeDir.E;
    const bit = east ? WALL_E : WALL_S;
    const ncx = east ? cx + 1 : cx;
    const ncy = east ? cy : cy + 1;
    const cellAt = (k: number): number => (east ? k * CHUNK_SIZE + LAST : LAST * CHUNK_SIZE + k);

    if (chunkInRing(def.shape, ncx, ncy)) {
      const { type, door } = coarse.side(cx, cy, east ? Dir.E : Dir.S);
      const cell = cellAt(door);
      if (isTreeDoor(type)) {
        walls[cell] = (walls[cell] as number) & ~bit;
        if (type !== DoorType.Open) borderDoors.push({ cell, edge, type });
      } else if (type === DoorType.Lever) {
        const side = (hash32(seed, SALT_COARSE_LEVER, cx, cy, edge, 1) & 1) as 0 | 1;
        coarseLevers.push({ cell, edge, side });
      }
    } else {
      // Ring boundary: closed except base openings.
      for (let k = 0; k < CHUNK_SIZE; k++) {
        const cell = cellAt(k);
        const key = edgeKey(gx0 + (cell & LAST), gy0 + (cell >> 5), edge);
        if (baseOpenings.has(key)) walls[cell] = (walls[cell] as number) & ~bit;
      }
    }
  }

  const { parent, depth } = chunkBfs(walls, 0);
  const levers = findLeverWalls(
    seed,
    cx,
    cy,
    walls,
    parent,
    depth,
    params.leverPermille,
    params.leverMinTreeDistance,
  );

  const plates: PlatePair[] = [];
  for (const dir of [Dir.N, Dir.E, Dir.S, Dir.W] as const) {
    const { type, door } = coarse.side(cx, cy, dir);
    if (type !== DoorType.Plate) continue;
    let doorCell: number;
    let cxA = cx;
    let cyA = cy;
    let d: EdgeDir;
    let sideFlag: 0 | 1 = 0;
    switch (dir) {
      case Dir.E:
        doorCell = door * CHUNK_SIZE + LAST;
        d = EdgeDir.E;
        break;
      case Dir.S:
        doorCell = LAST * CHUNK_SIZE + door;
        d = EdgeDir.S;
        break;
      case Dir.W:
        doorCell = door * CHUNK_SIZE;
        cxA = cx - 1;
        d = EdgeDir.E;
        sideFlag = 1;
        break;
      default:
        doorCell = door;
        cyA = cy - 1;
        d = EdgeDir.S;
        sideFlag = 1;
    }
    const cells = placePlates(seed, walls, doorCell, params.plateMaxDistanceCells, cxA, cyA, d, sideFlag);
    plates.push({ dir, doorCell, cells });
  }

  return { cx, cy, walls, levers, coarseLevers, borderDoors, plates, cache: cacheSpot(seed, cx, cy) };
}
