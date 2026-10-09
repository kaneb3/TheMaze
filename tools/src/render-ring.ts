// Render a whole (small) ring to PNG: walls, openings, gate slots, levers, doors, plates, caches.
//   npm run render-ring -- --seed 1 --ring 3 --outer 4 --inner 2 --scale 4 --out tools/out/ring.png

import { mkdirSync, writeFileSync } from 'node:fs';
import { dirname, resolve } from 'node:path';
import { defaultRingLiveParams } from '@lantern/server/config';
import { CHUNK_SIZE, Dir, DoorType, EdgeDir, type RingGenerator } from '@lantern/server/maze';
import { Image } from './png.js';
import { parseRingArgs } from './ring-cli.js';

type RGB = readonly [number, number, number];
const C = {
  void: [28, 28, 34],
  floor: [236, 224, 196],
  wall: [48, 38, 30],
  entrance: [40, 110, 230],
  arrival: [40, 190, 210],
  gate: [30, 170, 60],
  slot: [170, 220, 170],
  lever: [240, 140, 20],
  coarseLever: [210, 50, 30],
  narrow: [140, 60, 200],
  plateDoor: [200, 20, 60],
  plate: [250, 150, 190],
  cache: [230, 190, 30],
} satisfies Record<string, RGB>;

export function renderRing(gen: RingGenerator, s: number): Image {
  const B = gen.def.shape.outerHalf * CHUNK_SIZE;
  const size = 2 * B * s + 1;
  const img = new Image(size, size, C.void);
  const px = (x: number) => (x + B) * s;
  const fillCell = (x: number, y: number, rgb: RGB) => img.rect(px(x) + 1, px(y) + 1, s - 1, s - 1, rgb);
  const eastLine = (x: number, y: number, rgb: RGB) => img.rect(px(x + 1), px(y), 1, s + 1, rgb);
  const southLine = (x: number, y: number, rgb: RGB) => img.rect(px(x), px(y + 1), s + 1, 1, rgb);

  // Floors.
  for (let y = -B; y < B; y++) for (let x = -B; x < B; x++) if (gen.cellInRing(x, y)) fillCell(x, y, C.floor);

  // Features from chunks.
  const density = defaultRingLiveParams(gen.def.ringIndex).cacheDensityPermille;
  const b = gen.def.shape.outerHalf;
  for (let cy = -b; cy < b; cy++) {
    for (let cx = -b; cx < b; cx++) {
      if (!gen.chunkInRing(cx, cy)) continue;
      const ch = gen.chunk(cx, cy);
      const gx = (c: number) => cx * CHUNK_SIZE + (c & 31);
      const gy = (c: number) => cy * CHUNK_SIZE + (c >> 5);
      if (ch.cache.roll < density) fillCell(gx(ch.cache.cell), gy(ch.cache.cell), C.cache);
      for (const p of ch.plates) for (const c of p.cells) fillCell(gx(c), gy(c), C.plate);
      for (const d of ch.borderDoors) {
        const rgb = d.type === DoorType.Plate ? C.plateDoor : C.narrow;
        fillCell(gx(d.cell), gy(d.cell), rgb);
        fillCell(
          gx(d.cell) + (d.edge === EdgeDir.E ? 1 : 0),
          gy(d.cell) + (d.edge === EdgeDir.S ? 1 : 0),
          rgb,
        );
      }
    }
  }

  // Walls (every edge with at least one in-ring side).
  for (let y = -B - 1; y < B; y++) {
    for (let x = -B - 1; x < B; x++) {
      const here = gen.cellInRing(x, y);
      if ((here || gen.cellInRing(x + 1, y)) && !gen.isOpen(x, y, Dir.E)) eastLine(x, y, C.wall);
      if ((here || gen.cellInRing(x, y + 1)) && !gen.isOpen(x, y, Dir.S)) southLine(x, y, C.wall);
    }
  }

  // Shortcut walls drawn over the plain walls.
  for (let cy = -b; cy < b; cy++) {
    for (let cx = -b; cx < b; cx++) {
      if (!gen.chunkInRing(cx, cy)) continue;
      const ch = gen.chunk(cx, cy);
      const draw = (cell: number, edge: EdgeDir, rgb: RGB) => {
        const x = cx * CHUNK_SIZE + (cell & 31);
        const y = cy * CHUNK_SIZE + (cell >> 5);
        if (edge === EdgeDir.E) eastLine(x, y, rgb);
        else southLine(x, y, rgb);
      };
      for (const l of ch.levers) draw(l.cell, l.edge, C.lever);
      for (const l of ch.coarseLevers) draw(l.cell, l.edge, C.coarseLever);
    }
  }

  // Openings and gate slots: a 3×3-cell marker so they're visible at a glance (in-ring cells only).
  const marker = (x: number, y: number, rgb: RGB) => {
    for (let dy = -1; dy <= 1; dy++)
      for (let dx = -1; dx <= 1; dx++) if (gen.cellInRing(x + dx, y + dy)) fillCell(x + dx, y + dy, rgb);
  };
  for (const o of gen.outerOpenings)
    marker(o.edge.x, o.edge.y, o.kind === 'entrance' ? C.entrance : C.arrival);
  for (const g of gen.gateSlots) marker(g.edge.x, g.edge.y, g.active ? C.gate : C.slot);
  return img;
}

const { values, num, gen } = parseRingArgs({
  scale: { type: 'string', default: '4' },
  out: { type: 'string', default: 'tools/out/ring.png' },
});
// npm runs workspace scripts from tools/, so resolve relative to where npm was invoked.
const out = resolve(process.env.INIT_CWD ?? process.cwd(), String(values.out));
const img = renderRing(gen, num('scale'));
mkdirSync(dirname(out), { recursive: true });
writeFileSync(out, img.toPng());

const chunks = gen.coarse.chunkCount;
console.log(`ring ${gen.def.ringIndex} (seed ${gen.def.seed}): ${chunks} chunks, ${chunks * 1024} cells`);
console.log(`wrote ${out} (${img.width}x${img.height})`);
console.log(
  'legend: blue=entrance  cyan=arrival  green=active gate  pale green=reserved slot  orange=lever wall\n' +
    '        red line=coarse lever door  purple=narrow door  crimson=twin-plate door  pink=plates  gold=cache',
);
