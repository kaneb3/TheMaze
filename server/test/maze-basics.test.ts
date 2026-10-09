import { readdirSync, readFileSync } from 'node:fs';
import { join } from 'node:path';
import fc from 'fast-check';
import { describe, expect, it } from 'vitest';
import { game } from '../src/config/game.js';
import {
  decodeEdgeKey,
  edgeKey,
  hash32,
  LruCache,
  Mulberry32,
  ringChunkCount,
  shapeForRho,
  shapeFromArea,
} from '../src/maze/index.js';

describe('hash32', () => {
  it('returns uint32 and depends on every input and on order', () => {
    const h = hash32(1, 2, 3);
    expect(Number.isInteger(h) && h >= 0 && h <= 0xffffffff).toBe(true);
    expect(hash32(1, 2, 3)).toBe(h);
    expect(hash32(1, 2, 4)).not.toBe(h);
    expect(hash32(3, 2, 1)).not.toBe(h);
    expect(hash32(1, 2)).not.toBe(hash32(1, 2, 0));
    expect(hash32(-1)).not.toBe(hash32(1));
  });

  it('is roughly uniform in its low bits (permille draws)', () => {
    let hits = 0;
    const n = 100_000;
    for (let i = 0; i < n; i++) if (hash32(7, i) % 1000 < 150) hits++;
    expect(hits / n).toBeGreaterThan(0.14);
    expect(hits / n).toBeLessThan(0.16);
  });
});

describe('Mulberry32', () => {
  it('randInt stays in range', () => {
    fc.assert(
      fc.property(fc.nat(0xffffffff), fc.integer({ min: 1, max: 1 << 20 }), (seed, n) => {
        const r = new Mulberry32(seed);
        for (let i = 0; i < 20; i++) {
          const v = r.randInt(n);
          expect(Number.isInteger(v) && v >= 0 && v < n).toBe(true);
        }
      }),
    );
  });

  it('chance(0) never and chance(1000) always', () => {
    const r = new Mulberry32(1);
    for (let i = 0; i < 1000; i++) {
      expect(r.chance(0)).toBe(false);
      expect(r.chance(1000)).toBe(true);
    }
  });
});

describe('edge keys', () => {
  it('round-trip', () => {
    fc.assert(
      fc.property(
        fc.integer({ min: -(1 << 20) + 1, max: (1 << 20) - 1 }),
        fc.integer({ min: -(1 << 20) + 1, max: (1 << 20) - 1 }),
        fc.constantFrom(0 as const, 1 as const),
        (x, y, d) => {
          expect(decodeEdgeKey(edgeKey(x, y, d))).toEqual({ x, y, d });
        },
      ),
    );
  });
});

describe('shape from area (spec §10.3)', () => {
  const opts = {
    rho: game.ringThicknessRatio,
    rhoMin: game.ringThicknessRatioMin,
    rhoMax: game.ringThicknessRatioMax,
  };

  it('5,000 chunks at rho 0.25 gives about b = 54, T = 13', () => {
    const s = shapeForRho(5000, 0.25);
    expect(s.outerHalf).toBeGreaterThanOrEqual(52);
    expect(s.outerHalf).toBeLessThanOrEqual(56);
    expect(s.thickness).toBe(13);
  });

  it('covers at least the requested area, with a valid shape and bounded overshoot', () => {
    fc.assert(
      fc.property(fc.integer({ min: game.ringMinChunks, max: game.ringMaxChunks }), (chunks) => {
        const s = shapeFromArea(chunks, opts);
        expect(s.innerHalf).toBeGreaterThanOrEqual(1);
        expect(s.outerHalf).toBeGreaterThan(s.innerHalf);
        expect(s.chunks).toBe(ringChunkCount(s));
        expect(s.chunks).toBeGreaterThanOrEqual(chunks);
        expect(s.chunks).toBeLessThan(chunks * 1.25 + 64);
      }),
    );
  });

  it('raises rho to nest inside the previous ring when possible', () => {
    const free = shapeFromArea(5000, opts);
    const nested = shapeFromArea(5000, { ...opts, preferMaxOuterHalf: free.outerHalf - 5 });
    expect(nested.outerHalf).toBeLessThanOrEqual(free.outerHalf - 5);
    expect(nested.rho).toBeGreaterThan(free.rho);
    const impossible = shapeFromArea(5000, { ...opts, preferMaxOuterHalf: 10 });
    expect(impossible.outerHalf).toBeGreaterThan(10);
  });
});

describe('LruCache', () => {
  it('evicts the least recently used entry', () => {
    const c = new LruCache<number, string>(2);
    c.set(1, 'a');
    c.set(2, 'b');
    c.get(1);
    c.set(3, 'c');
    expect(c.get(2)).toBeUndefined();
    expect(c.get(1)).toBe('a');
    expect(c.size).toBe(2);
  });
});

describe('determinism hygiene', () => {
  it('no Math.random or Date.now anywhere in /maze', () => {
    const dir = join(import.meta.dirname, '../src/maze');
    for (const f of readdirSync(dir)) {
      const src = readFileSync(join(dir, f), 'utf8');
      expect(src, f).not.toMatch(/Math\.random|Date\.now/);
    }
  });
});
