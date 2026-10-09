import { describe, expect, it } from 'vitest';
import { slice, sliceRingGenParams } from '../src/config/game.js';
import { Dir, DoorType } from '../src/maze/index.js';
import { analyseRing, makeRing } from './helpers.js';

describe('vertical slice ring (spec §16.0)', () => {
  it('enables every generation feature', () => {
    const p = sliceRingGenParams();
    for (const k of ['narrowPermille', 'platePermille', 'leverPermille', 'coarseLeverPermille'] as const) {
      expect(p[k], k).toBeGreaterThan(0);
    }
  });

  it('generates a perfect base maze with narrow and twin-plate doors present', () => {
    const gen = makeRing(1, 1, slice.ringShape, sliceRingGenParams());
    const { cells, openEdges, components } = analyseRing(gen, false);
    expect(openEdges).toBe(cells - 1);
    expect(components).toBe(1);

    const seen = new Set<number>();
    const b = slice.ringShape.outerHalf;
    for (let cy = -b; cy < b; cy++)
      for (let cx = -b; cx < b; cx++)
        if (gen.chunkInRing(cx, cy))
          for (const d of [Dir.E, Dir.S] as const) seen.add(gen.coarse.side(cx, cy, d).type);
    for (const t of [DoorType.Narrow, DoorType.Plate, DoorType.Lever])
      expect(seen.has(t), `door type ${t}`).toBe(true);
  });
});
