// Coarse maze over a ring's chunks (spec §5.4): randomised Kruskal spanning tree, one door per open
// coarse edge, tree-door features (twin-plate / narrow) and closed coarse lever doors on non-tree edges.

import { hash32, SALT_COARSE, SALT_COARSE_LEVER, SALT_DOOR, SALT_NARROW, SALT_PLATE } from './hash.js';
import { chunkInRing } from './geometry.js';
import { Mulberry32 } from './prng.js';
import { CHUNK_SIZE, Dir, EdgeDir, type RingDef } from './types.js';

/** Type of the coarse edge between two adjacent chunks. */
export const DoorType = {
  /** No door: a wall (non-tree edge without a lever, or not between two in-ring chunks). */
  None: 0,
  /** Open tree door. */
  Open: 1,
  /** Open tree door that carts can't pass. */
  Narrow: 2,
  /** Tree door sealed by a twin-plate door (counts as open in the base layout). */
  Plate: 3,
  /** Closed coarse lever door on a non-tree edge (opening it adds a loop). */
  Lever: 4,
} as const;
export type DoorType = (typeof DoorType)[keyof typeof DoorType];

export function isTreeDoor(t: DoorType): boolean {
  return t === DoorType.Open || t === DoorType.Narrow || t === DoorType.Plate;
}

export class CoarseLayout {
  readonly outerHalf: number;
  readonly innerHalf: number;
  /** Width of the bounding chunk grid (2b). */
  readonly width: number;
  /** Per chunk id: type / door offset of the edge to its east and south neighbours. */
  readonly eastType: Uint8Array;
  readonly southType: Uint8Array;
  readonly eastDoor: Uint8Array;
  readonly southDoor: Uint8Array;
  readonly chunkCount: number;
  readonly treeEdgeCount: number;

  constructor(def: RingDef) {
    const { seed, shape, params } = def;
    const b = shape.outerHalf;
    this.outerHalf = b;
    this.innerHalf = shape.innerHalf;
    const width = 2 * b;
    this.width = width;
    const n = width * width;
    this.eastType = new Uint8Array(n);
    this.southType = new Uint8Array(n);
    this.eastDoor = new Uint8Array(n);
    this.southDoor = new Uint8Array(n);

    // Candidate edges in canonical order: row-major over chunks, east before south. Encoded id*2+d.
    const edges: number[] = [];
    let chunkCount = 0;
    for (let cy = -b; cy < b; cy++) {
      for (let cx = -b; cx < b; cx++) {
        if (!chunkInRing(shape, cx, cy)) continue;
        chunkCount++;
        const id = this.id(cx, cy);
        if (chunkInRing(shape, cx + 1, cy)) edges.push(id * 2 + EdgeDir.E);
        if (chunkInRing(shape, cx, cy + 1)) edges.push(id * 2 + EdgeDir.S);
      }
    }
    this.chunkCount = chunkCount;

    // Fisher–Yates shuffle with the coarse PRNG.
    const rng = new Mulberry32(hash32(seed, SALT_COARSE));
    for (let i = edges.length - 1; i > 0; i--) {
      const j = rng.randInt(i + 1);
      const tmp = edges[i] as number;
      edges[i] = edges[j] as number;
      edges[j] = tmp;
    }

    // Kruskal with union-find (path halving, union by size).
    const parent = new Int32Array(n);
    const size = new Int32Array(n).fill(1);
    for (let i = 0; i < n; i++) parent[i] = i;
    const find = (x: number): number => {
      while (parent[x] !== x) {
        const p = parent[parent[x] as number] as number;
        parent[x] = p;
        x = p;
      }
      return x;
    };

    const isTree = new Uint8Array(edges.length);
    let treeEdges = 0;
    for (let i = 0; i < edges.length; i++) {
      const e = edges[i] as number;
      const idA = e >> 1;
      const idB = (e & 1) === EdgeDir.E ? idA + 1 : idA + width;
      let ra = find(idA);
      let rb = find(idB);
      if (ra === rb) continue;
      if ((size[ra] as number) < (size[rb] as number)) [ra, rb] = [rb, ra];
      parent[rb] = ra;
      size[ra] = (size[ra] as number) + (size[rb] as number);
      isTree[i] = 1;
      treeEdges++;
    }
    this.treeEdgeCount = treeEdges;

    // Door types and offsets. Features are hashed per edge, so they don't depend on shuffle order.
    for (let i = 0; i < edges.length; i++) {
      const e = edges[i] as number;
      const idA = e >> 1;
      const d = (e & 1) as EdgeDir;
      const cxA = (idA % width) - b;
      const cyA = Math.floor(idA / width) - b;
      const cxB = d === EdgeDir.E ? cxA + 1 : cxA;
      const cyB = d === EdgeDir.E ? cyA : cyA + 1;

      let type: DoorType = DoorType.None;
      if (isTree[i]) {
        if (hash32(seed, SALT_PLATE, cxA, cyA, d) % 1000 < params.platePermille) type = DoorType.Plate;
        else if (hash32(seed, SALT_NARROW, cxA, cyA, d) % 1000 < params.narrowPermille)
          type = DoorType.Narrow;
        else type = DoorType.Open;
      } else if (hash32(seed, SALT_COARSE_LEVER, cxA, cyA, d) % 1000 < params.coarseLeverPermille) {
        type = DoorType.Lever;
      }
      if (type === DoorType.None) continue;

      const door = hash32(seed, SALT_DOOR, cxA, cyA, cxB, cyB) % CHUNK_SIZE;
      if (d === EdgeDir.E) {
        this.eastType[idA] = type;
        this.eastDoor[idA] = door;
      } else {
        this.southType[idA] = type;
        this.southDoor[idA] = door;
      }
    }
  }

  id(cx: number, cy: number): number {
    return (cy + this.outerHalf) * this.width + (cx + this.outerHalf);
  }

  /** Door type and offset of the coarse edge on side `dir` of chunk (cx, cy). */
  side(cx: number, cy: number, dir: Dir): { type: DoorType; door: number } {
    let ox = cx;
    let oy = cy;
    let east = true;
    switch (dir) {
      case Dir.N:
        oy = cy - 1;
        east = false;
        break;
      case Dir.E:
        break;
      case Dir.S:
        east = false;
        break;
      default:
        ox = cx - 1;
    }
    const b = this.outerHalf;
    if (ox < -b || ox >= b || oy < -b || oy >= b) return { type: DoorType.None, door: 0 };
    const id = this.id(ox, oy);
    return east
      ? { type: this.eastType[id] as DoorType, door: this.eastDoor[id] as number }
      : { type: this.southType[id] as DoorType, door: this.southDoor[id] as number };
  }
}
