# Project Lantern: Vision

> **Status:** current direction, adopted 2026-10-10 (see [ADR 0002](adr/0002-small-group-co-op.md)).
> This document is the source of truth for **what the game is**. Where it disagrees with
> [`project-lantern-spec.md`](../project-lantern-spec.md), this document wins. The spec is still the
> reference for the parts listed under "Carried over" below.

## The pitch

_You and up to three friends enter a vast hedge-and-stone maze at night. You aren't alone in here.
Between you, you have a few lanterns, one enchanted map that draws itself as you explore, and whatever
earlier challengers left behind: an old revolver, a handful of rounds, their notes. The maze is built
so no one gets through alone. Reach the centre together, or not at all._

Tone: the maze from _Harry Potter and the Goblet of Fire_. Night, fog, towering hedges, cold moonlight,
and the feeling that the maze itself is watching. Spooky, near-horror, never gore-driven.

## Pillars

1. **Together or not at all.** Small-group co-op (1–4 friends). The maze is designed so the group needs
   each other: shared scarce items, puzzles that take two or more people, and a threat that's easier
   to survive as a team.
2. **Exploring, not busywork.** Every system has to make the next corner more interesting. Decisions
   ("fight it, hide, or go another way?") are the gameplay; resource upkeep for its own sake is not.
3. **Fear of the dark, faith in the map.** First-person in fog makes the maze genuinely disorienting.
   The lantern pushes the dark back, and the Marauder's-Map-style parchment is how the group finds its
   way.
4. **Every shot counts.** Weapons are rare and ammunition scarcer. Running, hiding and rerouting are
   always real options, because a maze always has another way round.

## Decided

| Area        | Decision                                                                                                                                                 |
| ----------- | -------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Players     | Small-group co-op, **1–4 players**, friends playing together                                                                                             |
| Perspective | First-person 3D (Godot 4, GDScript)                                                                                                                      |
| Hosting     | **No dedicated servers to run.** Default: one player hosts and friends join via Steam (exact networking approach still to prove, see the open questions) |
| Setting     | Night maze of hedge and stone, Goblet-of-Fire mood (the look-dev art direction stands)                                                                   |
| Threat      | **Something lives in the maze.** Encounters are a choice: fight it (if you have the means) or turn back and find another route                           |
| Weapons     | An **old revolver** can be found in the maze, with very little ammunition                                                                                |
| Co-op       | Peak-style **shared, scarce items** and **teamwork puzzles**                                                                                             |
| Goal        | **Reach the centre together**                                                                                                                            |
| Map         | Hand-held parchment map (Tab), inked as the group explores. **Freehand markings are private** to the player who made them                                |
| Dropped     | The oil-and-haulage economy (camps, carts, withdrawal limits, supply requests); it felt like busywork without a giant shared world                       |
| Parked      | The server-wide MMO with a continent-sized shared maze (see "Parked" below)                                                                              |

## Starting design (to be proven by prototypes, not final)

These came out of the 2026-10-10 discussion and are the first things to test.

- **One map, one navigator.** The group has a single enchanted map; whoever holds it calls directions
  to the others. Map-reading becomes a co-op role.
- **One revolver, a few rounds.** Who carries it, and when to spend a shot, is a group decision.
- **Light is limited.** Only some players carry lanterns; the others stay close. (Whether light also
  runs out is open.)
- **Teamwork puzzles.** Pressure plates that must be held at the same time (the spec's twin-plate
  doors), levers that open a way for the others but close behind them, someone holding the light while
  someone else works, boosting a friend to see over the walls.
- **The threat shapes teamwork.** One player draws it away while the others solve a puzzle; splitting
  up covers more ground but is far more dangerous.
- **Full-screen map (proposed).** Tab stays the quick hand-held glance; a second key (M) spreads the
  map out full-screen to see everything found so far and write on it. Not yet confirmed.

## Open questions

1. **What is the creature?** Its look, senses (light? sound?), and whether it can be killed or only
   driven off.
2. **What's at the centre?** The Lighthouse from the old spec, a Goblet-style prize, or something else.
3. **Voice chat.** The old spec banned it (an MMO full of strangers). For friends co-op, **proximity
   voice** is a big part of the genre's fun. Revisit.
4. **Session shape.** One sitting per maze, or a saved campaign the group returns to? Same maze for
   everyone, or generated per group?
5. **Solo play.** Supported (scaled puzzles), or co-op only?
6. **Light as a resource.** Do lanterns run out (tension), or is light only limited by who carries one?
7. **Does the maze move?** Shifting walls, as in the film, would make the map a living tool.
8. **Networking approach.** Godot high-level multiplayer with Steam lobbies (e.g. GodotSteam), host
   authority, and how much anti-cheat a friends game needs (probably very little).
9. **Game name.** Still a placeholder.

## Carried over from the old spec

- **Maze generation** (§5, `server/src/maze`): deterministic, seeded, with golden vectors. The old rule
  "never generate the maze on the client" no longer applies; the host will need the generator in the
  game (port to GDScript and verify against the golden vectors, or another approach, when needed).
- **Movement feel** (§7, `client/player/`): the locomotion model, camera, footsteps and lantern motion.
  The server-mirroring rules only matter if networking needs them.
- **Art direction and production** (§16.0 "Art direction", "Art production"): Blender, CC0 textures,
  glTF into `client/assets/`, the look-dev scene.
- **Twin-plate doors and levers** (§5.6, §9.11, §9.13) as the seed of the teamwork puzzles.
- **Settings and menus** (`client/ui/`, `client/autoload/`): the parchment Esc menu, invert-Y, the map.

## Parked: the shared-world dream

The original spark was thousands of players sharing the drive to solve one enormous, continent-sized
riddle, with the map slowly filling with light. It's parked, not binned: it's too big and too risky for
a first project (it needs a crowd, a live service and moderation). If the co-op game finds an
audience, a light, **asynchronous** shared layer could come later (other groups' progress or notes
showing up in your maze, Death Stranding style) without running a live MMO.

## Plan: prove it's fun, one prototype at a time

Each step is small and playable, and ends with the user playing it and deciding what's next. These
replace the old vertical slice (spec §16.0, S1–S8).

| #   | Prototype                                                                                                                   | What it answers                        |
| --- | --------------------------------------------------------------------------------------------------------------------------- | -------------------------------------- |
| P1  | **One encounter, solo**, in the look-dev: a creature stalking the maze, a findable revolver with 3 rounds, fight-or-reroute | Does the core moment give you chills?  |
| P2  | **Two players on one network** (local/LAN), shared items, one twin-plate door                                               | Does working together feel good?       |
| P3  | **Steam lobbies**: friends join over the internet                                                                           | Can friends actually play it together? |
| P4  | **A whole small maze, start to centre**: generated maze, puzzles placed, the goal                                           | Is a full run fun?                     |

Stop and report at the end of each prototype.
