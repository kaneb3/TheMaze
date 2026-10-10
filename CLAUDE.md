# Project Lantern: notes for Claude

**Read [`docs/vision.md`](docs/vision.md) before building anything.** Since 2026-10-10 the game is a
small-group co-op maze (1–4 friends): a spooky Goblet-of-Fire-style night maze, a creature you fight
or avoid, a scarce revolver, shared items and teamwork puzzles. It is **not** the server-wide MMO in
`project-lantern-spec.md` any more ([ADR 0002](docs/adr/0002-small-group-co-op.md)).

- Don't build the spec's MMO systems (oil economy, camps, carts, game server, pacing, anti-cheat,
  trust, moderation). The spec's banner lists which sections are still a reference.
- Work prototype by prototype (vision doc, "Plan": P1–P4) and stop to report at the end of each.
  Open questions in the vision doc are the user's to answer; ask, don't guess.
- The user prefers going through decisions one point at a time, in plain language.

## Working in this repo

- The repo root is the Godot 4.7 project; Godot code lives in `client/` (ADR 0001). The TypeScript
  workspace (`server/src/maze` generator, `tools/`) keeps its own checks: `npm run check`.
- Godot tests are headless scripts: `godot --headless --path . --script res://client/tests/<name>_test.gd`
  (each prints ok/FAIL lines and exits non-zero on failure). Run the ones near your change, and
  `pause_menu_test` / `map_screen_test` after touching `fp_controller.gd` or `look_dev.gd`.
- Look at what you build: `godot --path . --resolution 1600x900 -- --shot=<png>` saves a look-dev
  screenshot (`--menu`, `--map`, `--mapall` and other flags are documented in `look_dev.gd`).
- Art: model in Blender (`art/`), CC0 textures only, glTF into `client/assets/`, licences recorded
  next to the assets. Critique every render honestly before showing it.
- Several Claude sessions may work in this repo at once. Pull before committing, commit only your
  own changes, and don't overwrite or revert files other sessions are editing.
