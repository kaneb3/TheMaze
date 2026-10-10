# ADR 0002: Small-group co-op instead of a server-wide MMO

**Status:** accepted (2026-10-10)

## Context

Spec v2 (`project-lantern-spec.md`) describes a massively multiplayer maze: one server-wide world,
thousands of players, months to reach the centre, paced by an oil-and-haulage economy (camps, carts,
withdrawal limits, supply requests) and protected by server authority, anti-cheat, trust scores and
moderation.

On review the user concluded that:

- a live MMO is not a realistic first project: it needs a large population from day one, a 24/7
  service, moderation and anti-cheat;
- the oil-and-haulage loop felt like busywork rather than exploring, and only existed to make a
  months-long MMO last;
- what they want is co-operative play where the group has to work together, in a spooky
  Goblet-of-Fire-style maze, with something to fight or avoid.

## Decision

Build a **small-group co-op game (1–4 friends)**. The current design is in
[`docs/vision.md`](../vision.md), which overrides the spec wherever they disagree.

- Drop the oil economy and everything that exists to support it.
- Park the server-wide world: no dedicated server, no pacing service, no trust or moderation systems.
  A light asynchronous shared layer may come later if the game finds an audience.
- Replace the vertical slice (spec §16.0, S1–S8) with prototypes P1–P4 (vision doc, "Plan").

## Consequences

- **Kept:** the deterministic maze generator and its golden vectors (`server/src/maze`, `shared/golden`),
  the Godot client work (movement, lantern, look-dev, map, Esc menu, settings) and the art pipeline.
- **No longer applies:** spec §0's "the server is the authority on everything", "never send unseen
  geometry to a client" and the rejection of client-side maze generation; §8 oil and supply lines;
  §10 pacing; §12 anti-cheat; §14 persistence; the MMO parts of §4, §6.5, §9, §13 and §15.
- The host needs the maze generator inside the game. When P4 needs it, port `server/src/maze` to
  GDScript (verified against the golden vectors) or find another route; decide then.
- The TypeScript workspace (`server/`, `tools/`, `sim/`) stays for the generator, its tests and the
  debug tools. The server-core code and Postgres setup are dormant, not deleted.
- The spec's voice-chat ban is reopened as a question for friends co-op (vision doc, open question 3).
