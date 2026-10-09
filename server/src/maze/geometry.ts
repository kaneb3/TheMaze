// Ring geometry (spec §5.1) and shape-from-area (spec §10.3).

import { CHUNK_CELLS, CHUNK_SHIFT, Dir, EdgeDir, type RingShape } from './types.js';

export function chunkInRing(shape: RingShape, cx: number, cy: number): boolean {
  const b = shape.outerHalf;
  const a = shape.innerHalf;
  if (cx < -b || cx > b - 1 || cy < -b || cy > b - 1) return false;
  return !(cx >= -a && cx <= a - 1 && cy >= -a && cy <= a - 1);
}

/** Rings are chunk-aligned, so a cell is in the ring iff its chunk is. */
export function cellInRing(shape: RingShape, x: number, y: number): boolean {
  return chunkInRing(shape, x >> CHUNK_SHIFT, y >> CHUNK_SHIFT);
}

export function ringChunkCount(shape: RingShape): number {
  const b = shape.outerHalf;
  const a = shape.innerHalf;
  return 4 * (b * b - a * a);
}

export function ringCellCount(shape: RingShape): number {
  return ringChunkCount(shape) * CHUNK_CELLS;
}

export function assertValidShape(shape: RingShape): void {
  const { outerHalf: b, innerHalf: a } = shape;
  if (!Number.isInteger(a) || !Number.isInteger(b) || a < 1 || b <= a) {
    throw new Error(`invalid ring shape: outerHalf=${b} innerHalf=${a} (need integers, b > a >= 1)`);
  }
  if (b * 32 >= EDGE_OFFSET) throw new Error(`ring too large for edge keys: outerHalf=${b}`);
}

// ---------------------------------------------------------------------------------------------
// Edge keys. Every edge is identified in owned form: cell (x, y) owns its E and S edges.
// Packed into a safe integer: x, y in (-2^20, 2^20).

const EDGE_OFFSET = 1 << 20;
const Y_SPAN = 1 << 22;

export function edgeKey(ox: number, oy: number, d: EdgeDir): number {
  return (ox + EDGE_OFFSET) * Y_SPAN + (oy + EDGE_OFFSET) * 2 + d;
}

/** Key of the edge on side `dir` of cell (x, y). */
export function edgeKeyDir(x: number, y: number, dir: Dir): number {
  switch (dir) {
    case Dir.N:
      return edgeKey(x, y - 1, EdgeDir.S);
    case Dir.E:
      return edgeKey(x, y, EdgeDir.E);
    case Dir.S:
      return edgeKey(x, y, EdgeDir.S);
    default:
      return edgeKey(x - 1, y, EdgeDir.E);
  }
}

export interface OwnedEdge {
  x: number;
  y: number;
  d: EdgeDir;
}

export function decodeEdgeKey(key: number): OwnedEdge {
  const ox = Math.floor(key / Y_SPAN);
  const rest = key - ox * Y_SPAN;
  const d = (rest & 1) as EdgeDir;
  const oy = (rest - d) / 2;
  return { x: ox - EDGE_OFFSET, y: oy - EDGE_OFFSET, d };
}

// ---------------------------------------------------------------------------------------------
// Shape from area (spec §10.3). Not part of generation output (the result is stored at lock),
// so floats are fine here.

export interface ShapeOptions {
  /** Starting thickness ratio ρ = T / b. */
  rho: number;
  rhoMin: number;
  rhoMax: number;
  /** Prefer outerHalf <= this (the previous ring's innerHalf), so rings shrink inward. */
  preferMaxOuterHalf?: number;
  rhoStep?: number;
}

export interface ShapeResult extends RingShape {
  thickness: number;
  chunks: number;
  rho: number;
}

export function shapeForRho(chunks: number, rho: number): ShapeResult {
  const b0 = Math.sqrt(chunks / (8 * rho - 4 * rho * rho));
  let t = Math.max(1, Math.round(rho * b0));
  let b = Math.ceil((chunks + 4 * t * t) / (8 * t));
  let a = b - t;
  if (a < 1) {
    // Nearly a filled square: a = 1 and solve 4b^2 - 4 >= chunks.
    b = Math.max(2, Math.ceil(Math.sqrt((chunks + 4) / 4)));
    a = 1;
    t = b - 1;
  }
  return { outerHalf: b, innerHalf: a, thickness: t, chunks: 4 * (b * b - a * a), rho: t / b };
}

export function shapeFromArea(chunks: number, opts: ShapeOptions): ShapeResult {
  const step = opts.rhoStep ?? 0.05;
  const rho0 = Math.min(opts.rhoMax, Math.max(opts.rhoMin, opts.rho));
  const first = shapeForRho(chunks, rho0);
  if (opts.preferMaxOuterHalf === undefined || first.outerHalf <= opts.preferMaxOuterHalf) return first;

  let last = first;
  for (let rho = rho0 + step; rho <= opts.rhoMax + 1e-9; rho += step) {
    last = shapeForRho(chunks, rho);
    if (last.outerHalf <= opts.preferMaxOuterHalf) return last;
  }
  // Impossible to nest: accept the larger ring (frames are independent), keeping the thickest shape.
  return last;
}
