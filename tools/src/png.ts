// Minimal truecolour PNG encoder (no dependencies).

import { crc32, deflateSync } from 'node:zlib';

export class Image {
  readonly data: Uint8Array;

  constructor(
    readonly width: number,
    readonly height: number,
    fill: readonly [number, number, number] = [0, 0, 0],
  ) {
    this.data = new Uint8Array(width * height * 3);
    for (let i = 0; i < width * height; i++) this.data.set(fill, i * 3);
  }

  set(x: number, y: number, rgb: readonly [number, number, number]): void {
    if (x < 0 || y < 0 || x >= this.width || y >= this.height) return;
    this.data.set(rgb, (y * this.width + x) * 3);
  }

  rect(x: number, y: number, w: number, h: number, rgb: readonly [number, number, number]): void {
    for (let j = 0; j < h; j++) for (let i = 0; i < w; i++) this.set(x + i, y + j, rgb);
  }

  toPng(): Buffer {
    const raw = Buffer.alloc((this.width * 3 + 1) * this.height);
    for (let y = 0; y < this.height; y++) {
      const row = y * (this.width * 3 + 1);
      raw[row] = 0; // filter: none
      raw.set(this.data.subarray(y * this.width * 3, (y + 1) * this.width * 3), row + 1);
    }
    const ihdr = Buffer.alloc(13);
    ihdr.writeUInt32BE(this.width, 0);
    ihdr.writeUInt32BE(this.height, 4);
    ihdr[8] = 8; // bit depth
    ihdr[9] = 2; // colour type: RGB
    return Buffer.concat([
      Buffer.from([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]),
      chunk('IHDR', ihdr),
      chunk('IDAT', deflateSync(raw)),
      chunk('IEND', Buffer.alloc(0)),
    ]);
  }
}

function chunk(type: string, body: Buffer): Buffer {
  const len = Buffer.alloc(4);
  len.writeUInt32BE(body.length);
  const typed = Buffer.concat([Buffer.from(type, 'ascii'), body]);
  const crc = Buffer.alloc(4);
  crc.writeUInt32BE(crc32(typed));
  return Buffer.concat([len, typed, crc]);
}
