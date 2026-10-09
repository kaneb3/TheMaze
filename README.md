# Project Lantern

A first-person, massively collaborative multiplayer maze. The design lives in
[`project-lantern-spec.md`](project-lantern-spec.md) (v2). Read it before changing anything.

## Layout

The repo root is the **Godot 4.7 project** (`project.godot`); Godot client code goes in `client/`.
Everything else is a TypeScript npm workspace, and each of those folders carries a `.gdignore` so the
Godot editor never scans it (`node_modules/.gdignore` is written by `postinstall`).

| Folder    | What                                                                                                                          |
| --------- | ----------------------------------------------------------------------------------------------------------------------------- |
| `client/` | Godot client (from M3)                                                                                                        |
| `server/` | Node/TS game server. `src/maze` = deterministic maze generation, `src/config/game.ts` = **all** tunables, `migrations/` = SQL |
| `tools/`  | Debug renderers (ring → PNG, chunk → ASCII), golden-vector tooling                                                            |
| `shared/` | `protocol.md`, `golden/` generation test vectors                                                                              |
| `sim/`    | Headless explorer bots (from M2.5)                                                                                            |
| `docs/`   | ADRs                                                                                                                          |

## Getting started

```sh
npm install
npm run check          # lint + format check + typecheck + tests
```

Tests run migrations against an in-process Postgres (PGlite), so no database is needed for `npm test`.
For a real database (needed from M2):

```sh
docker compose up -d   # Postgres 18 on localhost:5432 (lantern / lantern)
npm run migrate
```

## Debug tools

```sh
npm run render-ring -- --seed 1 --ring 3 --outer 4 --inner 2 --scale 4 --out tools/out/ring.png
npm run ascii-chunk -- --seed 1 --ring 3 --outer 4 --inner 2 --cx=-4 --cy=-1
```

## Determinism

Maze generation must give identical output for a seed forever (spec §5.2). `shared/golden/gen-v1.json`
pins hashes of generated output; CI fails if any change. `npm run golden:update` only appends new
cases and refuses to change existing vectors unless `GOLDEN_FORCE=1` (pre-launch only).
