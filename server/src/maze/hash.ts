// Deterministic 32-bit hashing (spec §5.2). Integer-only: Math.imul and >>> 0, no BigInt, no floats.
// NEVER change these constants or the algorithm after launch; bump GEN_VERSION instead.

export const GEN_VERSION = 1;

// Named salts. Values are arbitrary but frozen forever.
export const SALT_RING = 0x52494e47; // "RING"
export const SALT_COARSE = 0x434f4152; // "COAR"
export const SALT_CHUNK = 0x4348554e; // "CHUN"
export const SALT_DOOR = 0x444f4f52; // "DOOR"
export const SALT_GATE = 0x47415445; // "GATE"
export const SALT_CACHE = 0x43414348; // "CACH"
export const SALT_LEVER = 0x4c455652; // "LEVR"
export const SALT_COARSE_LEVER = 0x434c5652; // "CLVR"
export const SALT_NARROW = 0x4e415252; // "NARR"
export const SALT_PLATE = 0x504c4154; // "PLAT"

const C1 = 0xcc9e2d51;
const C2 = 0x1b873593;
const HASH_INIT = 0x2545f491;

/** murmur3 32-bit finaliser. */
export function fmix32(h: number): number {
  h ^= h >>> 16;
  h = Math.imul(h, 0x85ebca6b);
  h ^= h >>> 13;
  h = Math.imul(h, 0xc2b2ae35);
  h ^= h >>> 16;
  return h >>> 0;
}

/**
 * Hash a sequence of 32-bit integers to a uint32 (murmur3 body over each input, then fmix32).
 * Inputs are truncated to int32 (`| 0`), so negative coordinates are fine.
 */
export function hash32(...inputs: number[]): number {
  let h = HASH_INIT;
  for (let i = 0; i < inputs.length; i++) {
    let k = (inputs[i] as number) | 0;
    k = Math.imul(k, C1);
    k = (k << 15) | (k >>> 17);
    k = Math.imul(k, C2);
    h ^= k;
    h = (h << 13) | (h >>> 19);
    h = (Math.imul(h, 5) + 0xe6546b64) | 0;
  }
  h ^= inputs.length * 4;
  return fmix32(h);
}

/** Per-ring seed derived from the world seed (spec §5.2). */
export function ringSeed(worldSeed: number, ringIndex: number): number {
  return hash32(worldSeed, ringIndex, SALT_RING);
}
