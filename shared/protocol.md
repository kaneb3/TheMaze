# Network protocol reference

WebSocket, JSON at MVP (msgpack later behind a flag). Every message is `{ "t": "<type>", ...payload }`
and is validated with zod on the server; unknown or invalid messages are dropped and counted.

The starting message set is in the spec (§13). This file becomes the authoritative reference when the
server's zod schemas land in M2 (`server/src/net/protocol.ts`).

## Coordinates and wall encoding (fixed, M1)

- Positions are `(ring, x, y)` in the ring's own frame; cell = `floor(x), floor(y)`; chunk = `cell >> 5`.
- Grid `+x` → Godot `+X` (east), grid `+y` → Godot `+Z` (south). Cells are 4 m.
- Chunk walls: 1024 cells in row-major order (`index = ly * 32 + lx`), 2 bits each:
  bit0 = wall on the cell's east edge, bit1 = wall on its south edge. Packed 4 cells per byte
  (cell `i` → byte `i >> 2`, shift `(i & 3) * 2`) = 256 bytes per chunk.
- A cell's west/north walls belong to its west/north neighbour. On a ring boundary those edges are owned
  by out-of-ring cells; the server sends boundary openings separately (M2).
