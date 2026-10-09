// Boundary edges, fixed-point perimeter fractions, gate slots, entrances and arrivals (spec §5.7).

import { hash32, SALT_GATE } from './hash.js';
import { edgeKeyDir } from './geometry.js';
import { CHUNK_SIZE, Dir, type OuterOpening, type RingDef, type RingGenParams } from './types.js';

export const TWO_POW_32 = 4294967296;

/** A boundary edge, described from the in-ring cell (x, y); `dir` points out of the ring. */
export interface BoundaryEdge {
  x: number;
  y: number;
  dir: Dir;
  key: number;
}

/** Number of boundary edges around a square of half-width `half` chunks. */
export function boundaryEdgeCount(half: number): number {
  return 4 * 2 * half * CHUNK_SIZE;
}

/**
 * Edge `e` of the inner (hole) boundary, walking clockwise from the hole's top-left corner:
 * east along the top, south down the right, west along the bottom, north up the left.
 */
export function innerBoundaryEdge(innerHalf: number, e: number): BoundaryEdge {
  const A = innerHalf * CHUNK_SIZE;
  const side = 2 * A;
  const s = Math.floor(e / side);
  const k = e - s * side;
  let x: number;
  let y: number;
  let dir: Dir;
  switch (s) {
    case 0:
      x = -A + k;
      y = -A - 1;
      dir = Dir.S;
      break;
    case 1:
      x = A;
      y = -A + k;
      dir = Dir.W;
      break;
    case 2:
      x = A - 1 - k;
      y = A;
      dir = Dir.N;
      break;
    case 3:
      x = -A - 1;
      y = A - 1 - k;
      dir = Dir.E;
      break;
    default:
      throw new RangeError(`inner boundary edge ${e} out of range`);
  }
  return { x, y, dir, key: edgeKeyDir(x, y, dir) };
}

/** Edge `e` of the outer boundary, walking clockwise from the top-left corner. */
export function outerBoundaryEdge(outerHalf: number, e: number): BoundaryEdge {
  const B = outerHalf * CHUNK_SIZE;
  const side = 2 * B;
  const s = Math.floor(e / side);
  const k = e - s * side;
  let x: number;
  let y: number;
  let dir: Dir;
  switch (s) {
    case 0:
      x = -B + k;
      y = -B;
      dir = Dir.N;
      break;
    case 1:
      x = B - 1;
      y = -B + k;
      dir = Dir.E;
      break;
    case 2:
      x = B - 1 - k;
      y = B - 1;
      dir = Dir.S;
      break;
    case 3:
      x = -B;
      y = B - 1 - k;
      dir = Dir.W;
      break;
    default:
      throw new RangeError(`outer boundary edge ${e} out of range`);
  }
  return { x, y, dir, key: edgeKeyDir(x, y, dir) };
}

/** Map a 32-bit fixed-point fraction to an edge index in [0, count). Exact (product < 2^53). */
export function edgeIndexForT(tFix: number, count: number): number {
  return Math.floor((tFix * count) / TWO_POW_32);
}

/** Gate slot positions: tFix_i = floor((i·2^32 + J_i) / slotCount), jitter in [0.1, 0.9). */
export function gateSlotTFix(seed: number, slotCount: number): number[] {
  const out: number[] = [];
  for (let i = 0; i < slotCount; i++) {
    const j = 429496729 + Math.floor((hash32(seed, SALT_GATE, i) * 4) / 5);
    out.push(Math.floor((i * TWO_POW_32 + j) / slotCount));
  }
  return out;
}

/** Slots active at lock time: floor(j · slotCount / gateCount). */
export function activeSlotIndices(slotCount: number, gateCount: number): number[] {
  if (gateCount < 1 || gateCount > slotCount) {
    throw new Error(`gateCount ${gateCount} must be in [1, gateSlotCount=${slotCount}]`);
  }
  const out: number[] = [];
  for (let j = 0; j < gateCount; j++) out.push(Math.floor((j * slotCount) / gateCount));
  return out;
}

export function entranceTFix(count: number): number[] {
  const out: number[] = [];
  for (let j = 0; j < count; j++) out.push(Math.floor(((2 * j + 1) * TWO_POW_32) / (2 * count)));
  return out;
}

export interface GateSlot {
  index: number;
  tFix: number;
  active: boolean;
  edge: BoundaryEdge;
}

export function gateSlotsFor(def: RingDef): GateSlot[] {
  const { gateSlotCount, gateCount } = def.params;
  const active = new Set(activeSlotIndices(gateSlotCount, gateCount));
  const count = boundaryEdgeCount(def.shape.innerHalf);
  return gateSlotTFix(def.seed, gateSlotCount).map((tFix, index) => ({
    index,
    tFix,
    active: active.has(index),
    edge: innerBoundaryEdge(def.shape.innerHalf, edgeIndexForT(tFix, count)),
  }));
}

export interface PlacedOuterOpening extends OuterOpening {
  edge: BoundaryEdge;
}

export function outerOpeningsFor(def: RingDef): PlacedOuterOpening[] {
  const count = boundaryEdgeCount(def.shape.outerHalf);
  return def.outerOpenings.map((o) => ({
    ...o,
    edge: outerBoundaryEdge(def.shape.outerHalf, edgeIndexForT(o.tFix, count)),
  }));
}

export function entranceOpenings(count: number): OuterOpening[] {
  return entranceTFix(count).map((tFix) => ({ kind: 'entrance', tFix }));
}

/** Arrivals on ring k+1's outer edge = ring k's active gate slots. Depends only on ring k's seed & params. */
export function arrivalOpenings(prevSeed: number, prevParams: RingGenParams): OuterOpening[] {
  const tFix = gateSlotTFix(prevSeed, prevParams.gateSlotCount);
  return activeSlotIndices(prevParams.gateSlotCount, prevParams.gateCount).map((i) => ({
    kind: 'arrival',
    tFix: tFix[i] as number,
  }));
}
