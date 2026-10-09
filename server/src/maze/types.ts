// Shared maze types and constants.

/** Cells per chunk side. Never change after launch. */
export const CHUNK_SIZE = 32;
export const CHUNK_CELLS = CHUNK_SIZE * CHUNK_SIZE;
/** log2(CHUNK_SIZE), for cell → chunk via arithmetic shift (floor division for negatives too). */
export const CHUNK_SHIFT = 5;

/** Wall bits per cell (spec §5.3). */
export const WALL_E = 1;
export const WALL_S = 2;

/** Directions. N = -y, E = +x, S = +y, W = -x. */
export const Dir = { N: 0, E: 1, S: 2, W: 3 } as const;
export type Dir = (typeof Dir)[keyof typeof Dir];
export const DIRS: readonly Dir[] = [Dir.N, Dir.E, Dir.S, Dir.W];
export const DIR_DX: readonly number[] = [0, 1, 0, -1];
export const DIR_DY: readonly number[] = [-1, 0, 1, 0];
export const DIR_NAMES: readonly string[] = ['N', 'E', 'S', 'W'];
export const OPPOSITE: readonly Dir[] = [Dir.S, Dir.W, Dir.N, Dir.E];

/** Owned-edge form: cell (x, y) owns its east edge (0) and south edge (1). */
export const EdgeDir = { E: 0, S: 1 } as const;
export type EdgeDir = (typeof EdgeDir)[keyof typeof EdgeDir];

/** Ring shape in chunks: outer half-width b, inner (hole) half-width a, b > a >= 1. */
export interface RingShape {
  outerHalf: number;
  innerHalf: number;
}

/** Generation parameters, frozen when a ring is locked (spec §10.7). */
export interface RingGenParams {
  newestBiasPermille: number;
  narrowPermille: number;
  leverPermille: number;
  leverMinTreeDistance: number;
  coarseLeverPermille: number;
  platePermille: number;
  plateMaxDistanceCells: number;
  gateSlotCount: number;
  gateCount: number;
}

export type OuterOpeningKind = 'entrance' | 'arrival';

/** A boundary opening on a ring's outer edge, located by 32-bit fixed-point perimeter fraction. */
export interface OuterOpening {
  kind: OuterOpeningKind;
  tFix: number;
}

/** Everything needed to generate a ring deterministically. */
export interface RingDef {
  ringIndex: number;
  seed: number;
  shape: RingShape;
  params: RingGenParams;
  /** Entrances (ring 1) or arrivals of the previous ring's active gates. */
  outerOpenings: OuterOpening[];
}
