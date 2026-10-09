// Ring-level generation API: coarse maze, boundary openings, cached chunks, and wall queries with
// the append-only opening overlay applied (spec §5.10).

import { generateChunk, type ChunkContext, type ChunkData } from './chunk.js';
import { CoarseLayout } from './coarse.js';
import { gateSlotsFor, outerOpeningsFor, type GateSlot, type PlacedOuterOpening } from './gates.js';
import { assertValidShape, cellInRing, chunkInRing, edgeKeyDir } from './geometry.js';
import { LruCache } from './lru.js';
import { CHUNK_SHIFT, CHUNK_SIZE, DIR_DX, DIR_DY, Dir, WALL_E, WALL_S, type RingDef } from './types.js';

export interface RingGeneratorOptions {
  /** Chunk LRU size (spec §4.1, `chunkCacheSize`). */
  chunkCacheSize?: number;
}

const LAST = CHUNK_SIZE - 1;

export class RingGenerator {
  readonly def: RingDef;
  readonly coarse: CoarseLayout;
  readonly gateSlots: GateSlot[];
  readonly outerOpenings: PlacedOuterOpening[];
  /** Base boundary openings (outer openings + active gate slots) as owned-edge keys. */
  readonly baseOpenings: Set<number>;
  private readonly overlay = new Set<number>();
  private readonly cache: LruCache<number, ChunkData>;
  private readonly ctx: ChunkContext;

  constructor(def: RingDef, opts: RingGeneratorOptions = {}) {
    assertValidShape(def.shape);
    this.def = def;
    this.coarse = new CoarseLayout(def);
    this.gateSlots = gateSlotsFor(def);
    this.outerOpenings = outerOpeningsFor(def);
    this.baseOpenings = new Set<number>();
    for (const o of this.outerOpenings) this.baseOpenings.add(o.edge.key);
    for (const g of this.gateSlots) if (g.active) this.baseOpenings.add(g.edge.key);
    this.cache = new LruCache(opts.chunkCacheSize ?? 20_000);
    this.ctx = { def, coarse: this.coarse, baseOpenings: this.baseOpenings };
  }

  chunkInRing(cx: number, cy: number): boolean {
    return chunkInRing(this.def.shape, cx, cy);
  }

  cellInRing(x: number, y: number): boolean {
    return cellInRing(this.def.shape, x, y);
  }

  /** Generated chunk data (cached). Throws for chunks outside the ring. */
  chunk(cx: number, cy: number): ChunkData {
    if (!this.chunkInRing(cx, cy))
      throw new RangeError(`chunk (${cx}, ${cy}) is not in ring ${this.def.ringIndex}`);
    const key = this.coarse.id(cx, cy);
    const hit = this.cache.get(key);
    if (hit) return hit;
    const data = generateChunk(this.ctx, cx, cy);
    this.cache.set(key, data);
    return data;
  }

  /** Is the edge on side `dir` of cell (x, y) open in the generated (base) layout? */
  isOpenBase(x: number, y: number, dir: Dir): boolean {
    const nx = x + (DIR_DX[dir] as number);
    const ny = y + (DIR_DY[dir] as number);
    const aIn = this.cellInRing(x, y);
    const bIn = this.cellInRing(nx, ny);
    if (!aIn && !bIn) return false;
    if (!aIn || !bIn) return this.baseOpenings.has(edgeKeyDir(x, y, dir));

    let ox = x;
    let oy = y;
    let bit = WALL_E;
    switch (dir) {
      case Dir.N:
        oy = y - 1;
        bit = WALL_S;
        break;
      case Dir.S:
        bit = WALL_S;
        break;
      case Dir.W:
        ox = x - 1;
        break;
    }
    const walls = this.chunk(ox >> CHUNK_SHIFT, oy >> CHUNK_SHIFT).walls;
    return ((walls[((oy & LAST) << CHUNK_SHIFT) | (ox & LAST)] as number) & bit) === 0;
  }

  /** Effective state: generated layout with the opening overlay applied. */
  isOpen(x: number, y: number, dir: Dir): boolean {
    if (this.overlay.size > 0 && this.overlay.has(edgeKeyDir(x, y, dir))) return true;
    return this.isOpenBase(x, y, dir);
  }

  /** Add an edge to the opening overlay (levers, plates, discovered/extra gates). Idempotent. */
  openEdge(x: number, y: number, dir: Dir): void {
    const nx = x + (DIR_DX[dir] as number);
    const ny = y + (DIR_DY[dir] as number);
    if (!this.cellInRing(x, y) && !this.cellInRing(nx, ny)) {
      throw new RangeError(`edge (${x}, ${y}, ${dir}) doesn't touch ring ${this.def.ringIndex}`);
    }
    this.overlay.add(edgeKeyDir(x, y, dir));
  }

  overlayKeys(): ReadonlySet<number> {
    return this.overlay;
  }
}
