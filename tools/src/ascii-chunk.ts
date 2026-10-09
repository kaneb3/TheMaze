// Print one chunk as ASCII.
//   npm run ascii-chunk -- --seed 1 --ring 3 --outer 4 --inner 2 --cx=-4 --cy=-4   (negative numbers need the = form)

import { defaultRingLiveParams } from '@lantern/server/config';
import { CHUNK_SIZE, Dir, EdgeDir, type RingGenerator } from '@lantern/server/maze';
import { parseRingArgs } from './ring-cli.js';

export function asciiChunk(gen: RingGenerator, cx: number, cy: number): string {
  const ch = gen.chunk(cx, cy);
  const x0 = cx * CHUNK_SIZE;
  const y0 = cy * CHUNK_SIZE;
  const key = (lx: number, ly: number) => ly * CHUNK_SIZE + lx;

  const marks = new Map<number, string>();
  if (ch.cache.roll < defaultRingLiveParams(gen.def.ringIndex).cacheDensityPermille)
    marks.set(ch.cache.cell, '$');
  for (const p of ch.plates) for (const c of p.cells) marks.set(c, 'P');
  for (const o of gen.outerOpenings) {
    if (o.edge.x >> 5 === cx && o.edge.y >> 5 === cy)
      marks.set(key(o.edge.x & 31, o.edge.y & 31), o.kind === 'entrance' ? 'E' : 'A');
  }
  for (const g of gen.gateSlots) {
    if (g.edge.x >> 5 === cx && g.edge.y >> 5 === cy)
      marks.set(key(g.edge.x & 31, g.edge.y & 31), g.active ? 'G' : 'g');
  }
  const levers = new Set(ch.levers.map((l) => l.cell * 2 + l.edge));
  const coarseLevers = new Set(ch.coarseLevers.map((l) => l.cell * 2 + l.edge));

  const lines: string[] = [];
  for (let ly = 0; ly <= CHUNK_SIZE; ly++) {
    // Horizontal walls above row ly (the south edges of row ly - 1).
    let top = '';
    for (let lx = 0; lx < CHUNK_SIZE; lx++) {
      const x = x0 + lx;
      const y = y0 + ly;
      const open = gen.isOpen(x, y - 1, Dir.S);
      const c = ly > 0 ? key(lx, ly - 1) * 2 + EdgeDir.S : -1;
      top += '+' + (open ? '  ' : levers.has(c) ? '~~' : coarseLevers.has(c) ? '==' : '--');
    }
    lines.push(top + '+');
    if (ly === CHUNK_SIZE) break;

    let row = '';
    for (let lx = 0; lx <= CHUNK_SIZE; lx++) {
      const x = x0 + lx;
      const y = y0 + ly;
      const open = gen.isOpen(x - 1, y, Dir.E);
      const c = lx > 0 ? key(lx - 1, ly) * 2 + EdgeDir.E : -1;
      row += open ? ' ' : levers.has(c) ? '!' : coarseLevers.has(c) ? '#' : '|';
      if (lx < CHUNK_SIZE) row += (marks.get(key(lx, ly)) ?? ' ') + ' ';
    }
    lines.push(row);
  }
  lines.push(
    `chunk (${cx}, ${cy}) of ring ${gen.def.ringIndex}: ~~ ! lever wall, == # coarse lever door, ` +
      `P plate, $ cache, E entrance, A arrival, G gate, g reserved slot`,
  );
  return lines.join('\n');
}

const { num, gen } = parseRingArgs({
  cx: { type: 'string', default: '-1' },
  cy: { type: 'string', default: '-2' },
});
console.log(asciiChunk(gen, num('cx'), num('cy')));
