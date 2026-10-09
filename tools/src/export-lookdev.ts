// Export a small region of the vertical-slice Ring 1 as JSON for the Godot look-dev scene.
// Look-dev only: the real client never generates or receives unseen maze geometry (spec §0.6).
//   npm run export-lookdev -- --seed 1 --x0=-6 --y0=-128 --w 12 --h 12

import { mkdirSync, writeFileSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { parseArgs } from 'node:util';
import { game, slice, sliceRingGenParams } from '@lantern/server/config';
import { Dir, makeRingDef, RingGenerator } from '@lantern/server/maze';

const { values } = parseArgs({
  options: {
    seed: { type: 'string', default: '1' },
    x0: { type: 'string', default: '-6' },
    y0: { type: 'string', default: '-128' },
    w: { type: 'string', default: '12' },
    h: { type: 'string', default: '12' },
  },
});
const [seed, x0, y0, w, h] = (['seed', 'x0', 'y0', 'w', 'h'] as const).map((k) => Number(values[k]));

const gen = new RingGenerator(
  makeRingDef({
    worldSeed: seed! >>> 0,
    ringIndex: 1,
    shape: slice.ringShape,
    params: sliceRingGenParams(),
    entranceCount: game.entranceCount,
  }),
);

const inRegion = (x: number, y: number) => x >= 0 && y >= 0 && x < w! && y < h!;
const entranceKeys = new Set(gen.outerOpenings.map((o) => `${o.edge.x},${o.edge.y},${o.edge.dir}`));

// Closed edges in region-local coordinates, owned form: [x, y, "E"|"S"]. x/y may be -1 for the
// west/north region boundary. Region-boundary edges are sealed, except real ring entrances.
const walls: [number, number, 'E' | 'S'][] = [];
const entrances: [number, number, 'E' | 'S'][] = [];
for (let y = -1; y < h!; y++) {
  for (let x = -1; x < w!; x++) {
    for (const [d, nx, ny, dir] of [
      ['E', x + 1, y, Dir.E],
      ['S', x, y + 1, Dir.S],
    ] as const) {
      const a = inRegion(x, y);
      const b = inRegion(nx, ny);
      if (!a && !b) continue;
      const gx = x0! + x;
      const gy = y0! + y;
      const open = gen.isOpen(gx, gy, dir);
      const isEntrance =
        open &&
        (entranceKeys.has(`${gx},${gy},${dir}`) ||
          entranceKeys.has(
            `${gx + (d === 'E' ? 1 : 0)},${gy + (d === 'S' ? 1 : 0)},${d === 'E' ? Dir.W : Dir.N}`,
          ));
      if (isEntrance) entrances.push([x, y, d]);
      else if (!open || !(a && b)) walls.push([x, y, d]);
    }
  }
}

const out = {
  note: 'Look-dev sample of the vertical-slice Ring 1 (spec §16.0). Not used by the game client.',
  seed,
  origin: [x0, y0],
  width: w,
  height: h,
  cellSize: game.cellSizeM,
  wallHeight: game.wallHeightM,
  walls,
  entrances,
};
const path = join(import.meta.dirname, '../../client/lookdev/maze_sample.json');
mkdirSync(dirname(path), { recursive: true });
writeFileSync(path, JSON.stringify(out) + '\n');
console.log(`wrote ${path}: ${walls.length} walls, ${entrances.length} entrance(s)`);
