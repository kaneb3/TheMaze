# Project Lantern

A first-person co-op maze for 1–4 friends: a spooky, Goblet-of-Fire-style night maze, something
living in it that you fight or avoid, and puzzles that take teamwork. Reach the centre together, or
not at all.

- **What the game is:** [`docs/vision.md`](docs/vision.md). Read it first.
- **Why it changed:** [ADR 0002](docs/adr/0002-small-group-co-op.md). The game was first designed as a
  server-wide MMO; that premise is parked.
- **Reference for the parts that carried over** (maze generation, movement, art direction):
  [`project-lantern-spec.md`](project-lantern-spec.md) (v2). Its banner lists which sections still apply.

## Layout

The repo root is the **Godot 4.7 project** (`project.godot`); Godot client code goes in `client/`.
Everything else is a TypeScript npm workspace, and each of those folders carries a `.gdignore` so the
Godot editor never scans it (`node_modules/.gdignore` is written by `postinstall`).

| Folder    | What                                                                                                                                              |
| --------- | ------------------------------------------------------------------------------------------------------------------------------------------------- |
| `client/` | Godot client: `player/` movement & lantern, `ui/` map & Esc menu, `lookdev/` the playable look-dev scene                                          |
| `server/` | `src/maze` = deterministic maze generation (still used). The rest (game server, `config/game.ts`, `migrations/`) is from the MMO plan and dormant |
| `tools/`  | Debug renderers (ring → PNG, chunk → ASCII), golden-vector tooling                                                                                |
| `shared/` | `protocol.md`, `golden/` generation test vectors                                                                                                  |
| `sim/`    | Headless explorer bots (MMO plan; parked)                                                                                                         |
| `docs/`   | `vision.md` (the game), ADRs                                                                                                                      |

## Getting started

```sh
npm install
npm run check          # lint + format check + typecheck + tests
```

Tests run migrations against an in-process Postgres (PGlite), so no database is needed for `npm test`.
A real database was only needed for the MMO server, which is parked (ADR 0002).

## Running the game (look-dev)

Open the repo root in Godot 4.7 and press **F6** on `client/lookdev/LookDev.tscn` (it's also the main
scene). WASD walk · mouse look · Shift sprint · F lantern · Tab map · Esc menu · F11 fullscreen.

Godot tests run headless, one script each:

```sh
godot --headless --path . --script res://client/tests/movement_test.gd
```

The tests are the `*_test.gd` files in `client/tests/` (movement, wall sliding, the Esc menu, the map).
A screenshot run: `godot --path . --resolution 1600x900 -- --shot=out.png` (see `look_dev.gd` for the
other look-dev flags).

## Debug tools

```sh
npm run render-ring -- --seed 1 --ring 3 --outer 4 --inner 2 --scale 4 --out tools/out/ring.png
npm run ascii-chunk -- --seed 1 --ring 3 --outer 4 --inner 2 --cx=-4 --cy=-1
```

## Determinism

Maze generation must give identical output for a seed forever (spec §5.2). `shared/golden/gen-v1.json`
pins hashes of generated output; CI fails if any change. `npm run golden:update` only appends new
cases and refuses to change existing vectors unless `GOLDEN_FORCE=1` (pre-launch only).
