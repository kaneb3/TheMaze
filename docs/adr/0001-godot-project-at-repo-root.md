# ADR 0001: Godot project at the repo root

**Status:** accepted (2026-10-07)

## Context

The spec originally put the Godot project in `/client`. The Godot project already existed at the repo
root and was open in the editor; moving it would break the open editor session and the project's
`.godot/` import cache.

## Decision

Keep `project.godot` at the repo root (`res://`). Godot code and scenes go under `client/`
(`res://client/...`). Every non-Godot folder (`server/`, `tools/`, `shared/`, `sim/`, `docs/`,
`scripts/`, `node_modules/`) carries an empty `.gdignore` so the editor never scans or imports it.
`node_modules/.gdignore` is recreated by the root `postinstall` script after every `npm install`.

## Consequences

- New top-level non-Godot folders must get a `.gdignore` before anything is put in them.
- Root config files (`package.json`, `tsconfig.base.json`, etc.) are visible in Godot's FileSystem
  dock but are not imported.
