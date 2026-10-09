# Project Lantern — Build Spec for Claude Code

> **Codename:** Project Lantern (placeholder; the final game name is undecided)
> **One-liner:** A first-person, 3D, massively collaborative multiplayer maze so enormous it takes the whole community *months* to reach the centre. The shared map slowly lights up as players haul oil deeper into the dark.
> **Spec version:** 2 (2026-10-07)

### v2 changes (summary)
| Area | Change | Sections |
|---|---|---|
| Fast travel | Lantern tank is handed back to the departure node and refilled from the arrival node (closes the "teleport oil in the tank" loophole) | §7, §8.2 |
| Darkness | Moving through unlit cells is slower (`darkSpeedMultiplier`); touch geometry reduced to the current cell + corner edges; undiscovered gates are physically closed | §6.4, §7 |
| Settled rings | When the next ring opens, the previous ring's placed lanterns become permanent, so the map really does fill with light outside-in | §8.9, §10.1 |
| Carts / narrow edges | Narrow edges only on chunk (coarse) doors; new **coarse lever doors** create chunk-level loops that let carts route around them | §5.4, §5.6, §8.5 |
| Withdrawals | Base limit raised to ≥ pack size and scaled by trust; new **delivery withdrawals** tied to supply requests | §8.3, §8.7 |
| Coordination | Twin-plate doors have a plate pair on each side; contextual **pings** and **quick-chat** added | §9.13, §9.17 |
| Visibility | Flood-fill pre-pass, per-cell visibility cache, precomputed static light bitsets, worker threads, CPU budget | §4.1, §6.2 |
| Interest management | Three data classes (live entities / annotations / map layers) with one fog-leak invariant | §6.5 |
| Extra gates | Reserved **gate slots** chosen at lock time; "layout never changes" restated as generation + append-only opening overlay | §5.7, §5.9, §10.5 |
| Ring shape | Thickness set by ratio ρ = T/b instead of a fixed default; `f` fitted as a function of shape | §10.3 |
| Determinism details | All probabilities are integer per-mille draws; gate `t` is a 32-bit fixed-point value mapped to boundary **edges** | §5.2, §5.7 |
| Anti-cheat | Flagged accounts lose trust and go to review; no covert speed reduction | §12.3 |
| Repo | The Godot project lives at the repo root; non-Godot folders carry `.gdignore` | §4.2, §11.1 |

---

## 0. Instructions for Claude Code (read first)

1. **Read this entire document before writing any code.** Design decisions are deliberate, and several "obvious" features were explicitly rejected (see §2.2).
2. **Work milestone by milestone** (§16). M0 and M1 are done; the current plan is the **vertical slice** (§16.0, S1–S8). Stop at the end of each milestone and summarise what was built, what was tested, and any questions before continuing.
3. **Every gameplay number is a tunable.** Put all of them in a single config module (`server/src/config/game.ts`) with the defaults from §15. Never hard-code gameplay numbers elsewhere.
4. **The server is the authority on everything.** The client is a renderer and an input device. If you're unsure where logic belongs, it belongs on the server.
5. **Determinism is sacred.** Maze generation must produce identical output for the same seed on every machine, forever. Use the specified hash/PRNG (§5.2) and lock it with golden tests.
6. **Never send unseen maze geometry to a client.** This is the core anti-cheat guarantee (§12).
7. When you hit a question listed in §18 (Open Questions), ask rather than guess, unless the default is stated.
8. Write tests as you go (§17). A milestone isn't done until its acceptance criteria pass.
9. **The repo root is the Godot project** (`project.godot` lives there). Every non-Godot top-level folder (and `node_modules`) must contain a `.gdignore` file so the Godot editor doesn't scan or import it.

---

## 1. Vision & Pillars

### 1.1 The fantasy
You and thousands of strangers stand at the edge of an impossibly large, dark labyrinth. Far away above the walls, always visible, stands a vast **unlit lighthouse** at the centre. No one person can get there. Together, over months, the community maps the maze, builds camps, runs supply lines of lantern oil, opens shortcuts, and pushes the light inward, ring by ring. Finally, in one last community-wide supply effort, they haul enough oil to the core to **light the lighthouse**, and its light floods outward through the entire maze at once.

### 1.2 Pillars
1. **Collaboration over competition.** Everything one player discovers helps everyone. There is no race between players, only a shared expedition.
2. **Light is progress.** You can't map what you can't see. Oil powers light, and light reveals the maze. Over months the shared map fills with a warm glow from the outside in.
3. **Logistics is gameplay.** The frontier advances at the speed of the community's supply lines, not any one player's stamina.
4. **Months-long, self-pacing journey.** The maze is built in concentric rings, sized automatically from how fast the community actually explores.
5. **Disorientation is fun; the map is the cure.** First-person makes the maze genuinely confusing. The shared map, chalk, markers and signposts are how players beat it together.

### 1.3 Target scale
- Unknown player count at launch (could be hundreds, could be tens of thousands). The system must self-adjust (§10).
- Target time-to-centre: **~4 months** (configurable).
- Runs on a single modest server for launch; architecture allows later sharding by ring.

---

## 2. Decisions Log

### 2.1 Decided (do not change without asking)
| Area | Decision |
|---|---|
| Perspective | **First-person 3D** |
| Client engine | **Godot 4 (latest stable), GDScript** |
| Server | **TypeScript on Node.js (current LTS)**, WebSockets |
| Database | **PostgreSQL** |
| Platform | **Steam** (Windows first; Mac/Linux nice-to-have), via GodotSteam |
| Authority | Fully server-authoritative movement, visibility, and state |
| Fog of war | Server-side; unseen geometry never leaves the server |
| Maze generation | Seeded, deterministic, hierarchical (coarse chunk maze + per-chunk maze), generated on demand, never stored |
| Structure | Concentric **rings** connected by **gates**; rings generated lazily and sized automatically |
| Core resource | **Oil** (one resource only) |
| Fast travel | Between camps/hubs/depots, **only with an empty pack**. The lantern tank is handed back to the departure node and refilled from the arrival node (§7) |
| Darkness | Movement through unlit cells is slowed (`darkSpeedMultiplier`); light is speed as well as sight |
| Text communication | Contextual **pings** and fixed-phrase **quick-chat** only at MVP; no free-text chat (see §18) |
| The centre | An **unlit lighthouse** (the central tower landmark). The finale is the community hauling a huge amount of oil to fill it; ignition lights the whole maze live for everyone (§5.8) |
| Collaboration | Shared map, markers, footprints, chalk, thread, notes, bells, lanterns, flares, periscopes, expedition board, supply requests, shortcuts, camps, signposts, two-player doors, naming rights, chronicle, pings & quick-chat (§9) |

### 2.2 Explicitly rejected (do NOT implement)
- ❌ **Voice chat** of any kind
- ❌ **Daily step / movement limits** or stamina caps
- ❌ **Rested bonus** / offline-time speed boosts
- ❌ **Gate timers** (gates open immediately when discovered)
- ❌ Step donation / bonus lending
- ❌ Top-down / 2D gameplay view (the *map screen* is 2D; gameplay is first-person)
- ❌ Competitive racing between players
- ❌ Client-side maze generation

---

## 3. Core Gameplay Loop

1. **Spawn** at one of the entrance depots on the outer edge of the current outermost ring (Ring 1), with oil from the depot's endless supply.
2. **Fast-travel** (empty pack) to any active camp or gate hub. Your lantern tank is refilled from that camp's stock on arrival; **load up** your pack from the same stockpile.
3. **Explore** beyond the lit area. Your lantern burns oil. Everything your light touches is revealed to the **shared map** for everyone.
4. **Contribute**: place lanterns, chalk walls, mark dead ends, ring bells, claim a lead on the expedition board, haul oil to a forward camp, build a new camp, pull a shortcut lever.
5. **Discover a gate** to the next ring. It opens instantly for everyone, becomes a hub, and the chronicle records your name.
6. Repeat inward, ring after ring, until someone reaches the **core** and finds the cold lighthouse.
7. **The Kindling:** the whole community runs one final supply line to fill the lighthouse with oil. When it's full, it ignites live, and light sweeps outward through every ring.

Player roles emerge naturally: **scouts** (push the frontier), **haulers** (move oil), **builders** (lanterns, camps, shortcuts, signposts), **cartographers** (markers, naming, verifying).

---

## 4. Architecture

```
┌────────────────────┐        WebSocket (JSON → msgpack later)        ┌──────────────────────────────┐
│  Godot 4 client    │ ◀───────────────────────────────────────────▶ │  Node/TS game server         │
│  - FP controller   │   inputs, actions  ▶                          │  - session & auth            │
│  - chunk renderer  │   ◀ reveals, entities, corrections, events    │  - movement validation       │
│  - map screen      │                                                │  - visibility & reveal       │
│  - HUD / audio     │                                                │  - maze gen (deterministic)  │
└────────────────────┘                                                │  - oil / camps / tools       │
                                                                      │  - pacing service (cron)     │
┌────────────────────┐        same protocol                           │  - anti-cheat metrics        │
│  /sim explorer bots│ ◀───────────────────────────────────────────▶ └──────────────┬───────────────┘
└────────────────────┘                                                               │ write-behind
                                                                                     ▼
┌────────────────────┐                                                ┌──────────────────────────────┐
│  /tools admin CLI  │ ─────────── admin API (auth'd) ──────────────▶ │  PostgreSQL                  │
└────────────────────┘                                                └──────────────────────────────┘
```

### 4.1 Server internals
- **Single process** for MVP. Fixed **simulation tick at 20 Hz**.
- **In-memory world state** (players, entities, revealed chunk bitsets, camp stocks) with **write-behind persistence** to Postgres every `persistIntervalSec` (default 5 s), plus on shutdown.
- **Chunk wall cache:** LRU of generated chunk wall data (default 20,000 chunks). Chunks regenerate deterministically on a miss.
- **Coarse maze per ring:** computed once at boot (or on ring creation) and held in memory.
- **Interest management:** each player only receives data allowed by the three data classes in §6.5.
- **Visibility workers:** visibility/reveal computation runs in a `worker_threads` pool reading chunk wall data from `SharedArrayBuffer`s, so the 20 Hz tick on the main thread is never starved (§6.2). Pool size `visibilityWorkers` (default: CPU cores − 1).
- Libraries (suggested): `ws`, `postgres` (porsager) or `pg`, `zod` (message validation), `pino` (logging), `vitest` + `fast-check` (tests).

### 4.2 Repo layout (monorepo)
The repo root **is** the Godot project. TypeScript packages are npm workspaces. Every non-Godot folder carries a `.gdignore`; `node_modules/.gdignore` is written by a `postinstall` script.
```
project.godot  Godot 4 project file (root = res://)
/client        Godot client code & scenes (res://client/...)
/server        Node/TS game server
  /src
    /config      game.ts (ALL tunables), env.ts
    /maze        hash.ts, prng.ts, coarse.ts, chunk.ts, ring.ts, features.ts, gates.ts
    /world       state.ts, visibility.ts, movement.ts, reveal.ts, persistence.ts
    /systems     oil.ts, lanterns.ts, camps.ts, carts.ts, caches.ts, tools/*.ts
    /net         server.ts, protocol.ts (zod schemas), session.ts, auth.ts
    /pacing      stats.ts, sizing.ts, scheduler.ts, levers.ts, alerts.ts
    /anticheat   speed.ts, behaviour.ts, trust.ts
    /admin       api.ts
  /migrations    plain SQL migrations (NNN_name.sql) + tiny runner
  /test
/shared        protocol.md (message reference), golden/ (generation test vectors)
/sim           headless explorer bots (TS), load testing, pacing estimation
/tools         admin CLI, debug renderers (maze → PNG/ASCII)
/docs          ADRs (this spec lives at the repo root)
docker-compose.yml   (postgres for local dev)
```

---

## 5. World Model & Maze Generation

### 5.1 Units & coordinates
| Term | Definition |
|---|---|
| **Cell** | One square of the maze grid. **4 m × 4 m** in world space. Wall height ~4.5 m. |
| **Chunk** | **32 × 32 cells** (128 m square). Unit of generation, streaming, and reveal storage. |
| **Ring** | A square annulus of chunks with its **own coordinate frame**, centred on the origin. Identified by `ringIndex` (1 = outermost). |
| **Position** | `(ringIndex, x, y)`, where `x, y` are float cell coordinates in that ring's frame. Cell = `floor(x), floor(y)`. Chunk = `floor(cell / 32)`. |
| Axes | Grid `+x` → Godot world `+X`; grid `+y` → Godot world `+Z`. "East" = +x, "South" = +y. |

**Ring geometry:** a ring has outer half-width `b` and inner half-width `a` (in chunks, integers, `b > a ≥ 1`). A chunk `(cx, cy)` belongs to the ring if it is inside the outer square and outside the inner hole:
```
inOuter = -b <= cx <= b-1  &&  -b <= cy <= b-1
inHole  = -a <= cx <= a-1  &&  -a <= cy <= a-1
inRing  = inOuter && !inHole
ring chunk count = (2b)^2 - (2a)^2
```

**Why each ring has its own frame:** ring sizes are decided months apart by the pacing system (§10). Independent frames mean an inner ring can be any size without having been reserved at launch. Rings connect only through gates, matched by **perimeter fraction** `t ∈ [0,1)` (§5.7). In first person this is imperceptible. The map screen draws rings as nested schematic bands.

### 5.2 Determinism: hashing & PRNG
- All randomness derives from `worldSeed` (uint32) → `ringSeed = hash32(worldSeed, ringIndex, SALT_RING)`.
- **hash32:** combine integer inputs with a murmur3-style finaliser (`fmix32`) over each input in sequence. Implement with `Math.imul` and `>>> 0` (32-bit only, **no BigInt, no floats**).
- **PRNG:** `mulberry32(seed)` for sequential draws inside one generation call.
- **Integer draws only.** Every probability is an integer per-mille (`*Permille`), tested as `u32 % 1000 < permille`. Bounded integers use `randInt(n) = floor(u32 × n / 2³²)` (exact in doubles for `n < 2²¹`). No float comparisons decide generated content.
- Every generation function takes explicit seeds; **no global RNG, no `Math.random()`** anywhere in `/maze`.
- Salts are named constants (`SALT_RING`, `SALT_COARSE`, `SALT_CHUNK`, `SALT_DOOR`, `SALT_GATE`, `SALT_CACHE`, `SALT_LEVER`, `SALT_COARSE_LEVER`, `SALT_NARROW`, `SALT_PLATE`, ...). **Never change a salt or algorithm after launch.** Version the generator (`GEN_VERSION = 1`) and store it per ring.
- **Golden tests:** check in hashes of generated output for fixed seeds (`/shared/golden`). CI fails if any change.

### 5.3 Wall representation
- Each cell owns **2 bits**: `bit0 = wall on EAST edge`, `bit1 = wall on SOUTH edge`. A cell's west wall is the east wall of `(x-1, y)`; its north wall is the south wall of `(x, y-1)`.
- Chunk wall data = 32×32×2 bits = **256 bytes**.
- Edges on a chunk boundary are owned by the west/north cell (normal rule). Generation of a chunk therefore also needs to know the door decisions on its west and north boundaries (and writes its own east/south boundary from the coarse maze; see §5.5).
- Ring outer boundary and inner (hole) boundary edges are always walls, except at **openings**: **entrances** (Ring 1 outer edge only), **gates** (inner edge) and **arrivals** (outer edge of ring ≥ 2). Some boundary edges are owned by out-of-ring cells (e.g. the west edge of a ring cell next to the hole), so boundary openings are held as a per-ring **openings set** keyed by edge; chunk data mirrors it for the boundary edges the chunk owns, and the edge-query function consults it for the rest.

### 5.4 Coarse maze (per ring)
- Graph: nodes = chunks in the ring; edges = 4-neighbour adjacency between in-ring chunks.
- Algorithm: **randomised Kruskal** seeded with `hash32(ringSeed, SALT_COARSE)` → spanning tree.
- Result: set of **open coarse edges** (the tree). Each open coarse edge gets exactly one **door cell** on the shared chunk border, chosen as `hash32(ringSeed, SALT_DOOR, cxA, cyA, cxB, cyB) % 32` (A is the west/north chunk of the pair).
- **Tree doors** may carry a feature: **twin-plate** (`platePermille`) or, failing that, **narrow** (`narrowPermille`). See §5.6.
- **Coarse lever doors:** each *non-tree* coarse edge gets a closed lever door with probability `coarseLeverPermille`, at its own door cell (same door formula). Pulling it opens a permanent chunk-level loop. These are the only way to route around a narrow or twin-plate tree door.
- Kept in memory; computed at boot from the seed. Size is trivial (a 25k-chunk ring is a few hundred KB).

### 5.5 Chunk maze
- Each chunk is filled with a **perfect maze** over its 32×32 cells using the **Growing Tree** algorithm, seeded with `hash32(ringSeed, SALT_CHUNK, cx, cy)`.
- Growing Tree cell selection: with probability `newestBiasPermille` (per-mille) pick the newest cell (backtracker-like, long corridors), otherwise a random cell (Prim-like, branchy). It is a **per-ring parameter** (default 750), so ring themes can feel different. Removing a finished cell from the active list preserves list order.
- Boundary edges of the chunk are walls **except** door cells from open coarse edges.
- **Property:** spanning tree of chunks + spanning tree inside each chunk + exactly one door per open coarse edge ⇒ **the base ring is a perfect maze** (exactly one path between any two cells). "Base" means every lever wall and coarse lever door closed and every twin-plate door counted as an open edge. Test this.

### 5.6 Deterministic features (per edge / per cell)
Computed during chunk generation from hashes, never stored (except materialised state, §5.9):
| Feature | Rule (defaults) | Purpose |
|---|---|---|
| **Narrow doors** | **Tree** coarse doors (only) where `hash(SALT_NARROW, …) % 1000 < narrowPermille` and the door isn't twin-plate (ring 1 = 0, later rings default 150). In-chunk edges are never narrow. | Carts can't pass (§8.5) |
| **Lever walls** | Closed in-chunk walls with `hash(SALT_LEVER, …) % 1000 < leverPermille` (default 15) **and** whose two cells are ≥ `leverMinTreeDistance` (default 40) apart along the chunk's tree. The lever is on one side, chosen by a hash bit. | Permanent shortcuts (§9.11) |
| **Coarse lever doors** | Non-tree coarse edges with `hash(SALT_COARSE_LEVER, …) % 1000 < coarseLeverPermille` (default 200) | Chunk-level shortcuts; cart routes around narrow doors (§8.5) |
| **Twin-plate doors** | Tree coarse doors with `hash(SALT_PLATE, …) % 1000 < platePermille` (ring ≥ `plateMinRing` = 3, default 80). A **plate pair on each side**: two distinct cells within `plateMaxDistanceCells` (default 6) path distance of the door, inside the adjacent chunk. | Two-player cooperation (§9.13) |
| **Cache spots** | One candidate cell per chunk (`hash(SALT_CACHE, …) % 1024`) with a roll `0..999`; exists if `roll < cacheDensityPermille(ring)` **at materialisation time** | Oil + consumables (§8.4) |

Lever walls and coarse lever doors start **closed**, so the base maze stays perfect. Opening them adds loops.

### 5.7 Gates & entrances
- **Fixed-point `t`.** Perimeter fractions are 32-bit unsigned fixed-point values `tFix ∈ [0, 2³²)`, `t = tFix / 2³²`. All mapping is integer maths; `t` as a REAL is for display only.
- **Gate slots.** Each ring has `gateSlotCount` (default 12) **slots** on its inner boundary at `tFix_i = floor((i·2³² + J_i) / gateSlotCount)`, where `J_i = 429496729 + floor(hash32(ringSeed, SALT_GATE, i) × 4 / 5)` (i.e. jitter in `[0.1, 0.9)`). At lock time `gateCount` slots (default 5) are **active**: slot indices `floor(j × gateSlotCount / gateCount)` for `j = 0..gateCount-1`. The rest are **reserved** for the pacing service (§10.5).
- **Mapping `t` to an edge.** Walk the boundary **edges** clockwise from the top-left corner (east along the top, south down the right, west along the bottom, north up the left). A boundary of half-width `h` chunks has `P = 4 × 64h` edges; edge index `e = floor(tFix × P / 2³²)`. Each boundary edge touches exactly one in-ring cell, so corners are never ambiguous.
- A gate at `tFix` on ring *k*'s inner boundary connects to ring *k+1*'s **outer boundary** at the same `tFix` (an **arrival**). Ring *k+1*'s outer boundary is closed except at arrivals of active gates.
- **Entrances:** Ring 1 has `entranceCount` (default 4) entrances on its outer boundary at `t = (2j+1) / (2 × entranceCount)` (0.125, 0.375, 0.625, 0.875: the N/E/S/W midpoints). Each has an **entrance depot**.
- Gates are **hidden until revealed** like any cell, and an undiscovered gate is a **physically closed gate** (it reads as a wall in touch geometry, §6.4). **Discovery = the gate cell is revealed with light** (§6.3). Discovery opens the gate **immediately for everyone** (no timer).
- Optional per-ring `gateKeyRequirement` (default `none`; reserved for later, see §18).

### 5.8 The core & the Lighthouse (finale)

**Design rules:** reward the whole community, not one lucky player, and only promise what can be delivered. Mystery beats an announced prize.

**The core**
- After the final ring, the gates lead to the **Core**: a hand-authored area (Godot scene `Core.tscn`), not procedurally generated. It's a circular plaza around the base of the **Lighthouse**, the same tower players have seen on the horizon (§11.2) since day one.
- The core contains a **gate hub** per arrival gate (normal hub rules, §8.3), so supply lines can run into it.
- Number of rings: `plannedRingCount` (default 5) + core. The pacing system can be told to add or stop rings (§10).

**The Lighthouse**
- Arrives **cold and dark**. Its great lamp has a reservoir that needs `lighthouseOilRequired` oil.
- **The Kindling (finale phase):** begins when the first player enters the core. Any player can **deposit** oil into the reservoir at the base (same as a camp deposit; no withdrawals ever). Progress is shown in-world (a rising glow inside the tower's glass), on the map, in the chronicle, and on a world-wide HUD banner.
- Deposits are credited per player (`lighthouse_contributions`).
- **Sizing:** `lighthouseOilRequired` is set by the pacing service when the final ring is locked, using the measured community oil-delivery rate so the Kindling lasts about `kindlingTargetDays` (default 10):
  ```
  lighthouseOilRequired = oilDeliveredToCampsPerDay (7-day avg) × kindlingTargetDays × kindlingFactor (default 0.8)
  ```
  Clamp to `[lighthouseOilMin, lighthouseOilMax]`. The same live levers (§10.5) apply: hub stock top-ups if stalling, nothing if too fast.

**Ignition (the moment)**
- When the reservoir fills, the server schedules ignition `ignitionDelayMinutes` (default 30) ahead and announces it to every connected client and the alert webhook, so people can log in and gather. *(This is a short countdown to the event, not a gate timer.)*
- At ignition, every online client plays the ignition sequence: the lamp catches and a **wave of light sweeps outward** from the core through each ring in turn over `ignitionWaveSeconds` (default 300).
- **World state change:** the world is flagged `illuminated`. Every cell in every ring becomes **revealed and lit** (no oil needed, ambient light everywhere). The shared map turns completely gold, including corners nobody ever reached. All walls stay; the maze becomes freely explorable in full light.
- The chronicle records ignition with the date, total days elapsed, players involved, total oil hauled and total cells lit.

**The Wall of Names**
- The lighthouse interior has a spiral stair lined with the names of **every player who contributed anything** (revealed cells, oil delivered to any camp or the lighthouse, gates found, shortcuts opened, camps built). Each name shows the player's headline contribution (e.g. "12,408 cells lit · 3,200 oil hauled").
- Generated server-side at ignition from `player_stats`; the client renders it as text on the stair walls, searchable from a lighthouse terminal so players can find their own name.
- The top of the stair is the **lantern room**: from here players get the full view across the lit maze.

**First arrival (modest, deliverable)**
- The first player to enter the core gets a plaque at the core entrance and a chronicle entry. A further gift (e.g. a statue, or naming the next season's first ring) is an open question (§18). Keep it modest and in-game only.

**Proposed extras (confirm before building, see §18)**
- **Lore fragments:** torn pages from a previous, failed expedition found in caches (materialised on reveal like other cache contents), gradually explaining who built the maze, why it's dark, and what the lighthouse is for. The core answers the mystery.
- **Next season seed:** from the lantern room after ignition, a second dark maze is visible on the horizon, hinting at Season 2.

### 5.9 "Materialise on first reveal" principle
Any **tunable** parameter that affects generated content (cache density, cache contents) must be **materialised into the DB the first time the chunk is revealed**. Tuning a lever later then only affects unrevealed chunks, and nobody sees content change under their feet.

### 5.10 Wall layout = generation + opening overlay
- The **generated layout** of a locked ring (walls, doors, features, gate slots, active gates) never changes.
- All later changes live in an **append-only opening overlay** (`opened_walls`, §14): levers, coarse lever doors, twin-plate doors, discovered gates and pacing-activated reserved gate slots. The overlay can only ever **remove** walls.
- An overlay entry is created either by an in-world player action, or (for reserved gate slots) only on edges whose cells are still **unrevealed** on both sides, so no one ever sees a wall vanish.
- The effective wall at an edge = generated wall AND NOT in overlay.

---

## 6. Visibility, Light & Reveal

### 6.1 Light sources
A cell is **illuminated** for a player if any of these apply:
1. Within the player's **lantern radius** (`lanternRadiusCells`, default 6) while their lantern is lit, with line of sight.
2. Within **ambient light radius** of the ring (`ambientRadiusCells` per ring: Ring 1 = 2, later rings = 0), with line of sight.
3. **Lit cell**: within radius of a placed lantern served by a fuelled camp (§8.3), or within an active flare (§9.7).
4. Within a camp / depot / gate hub's own light radius (default 5).

### 6.2 Line of sight
- **Viewpoint = cell centre.** LOS is computed from the centre of the player's current cell (good enough for reveal; the client only ever renders revealed geometry).
- **Step 1, flood-fill pre-pass:** a sight line can only pass between cells through open edges, so first flood-fill from the player's cell through open edges, staying within Chebyshev radius `R = max light radius in play (cap 12)`. Only reached cells are candidates (typically 50–150 in a maze, versus 625).
- **Step 2, ray test:** for each candidate, cast a **grid DDA (Amanatides–Woo)** ray from viewpoint to the cell centre; the ray is blocked when it crosses a closed wall edge (ties through a grid corner are blocked if either side is walled).
- **Per-cell LOS cache:** the LOS set from a cell depends only on walls, so cache it as a 625-bit mask (~80 bytes) keyed by `(ring, cell)`, only for cells players currently occupy (LRU, `losCacheSize`, default 200,000). Invalidate entries within `R` of any overlay opening (§5.10).
- **Static light bitsets:** each placed lantern / camp / hub / depot writes its lit cells (LOS from its cell, its radius) into a per-chunk **lit bitset** (128 bytes) when it turns on, and clears it when it turns off. "Is this cell lit?" is a bit lookup. Only the player's own lantern and flares are evaluated live.
- **Visible set** = LOS cells that are illuminated (own lantern radius, lit bitset, ambient, flare).
- Recompute only when the player enters a new cell, the lantern toggles, or a light changes nearby. Runs in the visibility worker pool (§4.1).

### 6.3 Reveal → shared map
- Every newly visible cell not already in the ring's **revealed bitset** is added. Its walls become **shared knowledge**: all players can see that geometry on their map and in-world.
- Revealed bitset per chunk = 1024 bits = **128 bytes**, stored in `chunk_reveal`.
- **You can't map what you can't see:** cells you're standing in without light are NOT added to the shared map.
- Each reveal increments the **daily new-cells counter** (feeds pacing, §10) and is attributed to the revealing player (stats, naming rights).

### 6.4 Touch geometry (darkness collision)
To let the client collide correctly in darkness, the server sends **private touch data**: the 4 edges of the player's **current cell** plus the edges that meet its 4 corners (12 edges in total), enough for a 0.4 m-radius player to collide correctly. Touch data is never added to the shared map, never shown on the map screen, and discarded client-side when out of range. **Undiscovered gates are reported as closed.** Groping through the dark is possible but slow (`darkSpeedMultiplier`, §7) and reveals nothing to the shared map.

### 6.5 What the client receives (three data classes)
| Class | Examples | Sent when |
|---|---|---|
| **Live entities** | players, carts, thrown flares | Only inside the player's current visible set. Other players behind walls are never sent. |
| **Annotations** (placed, persistent) | chalk, notes, signposts, markers, placed lanterns, bells, camps, levers, plates, caches, gates | With `chunkSync`/deltas for chunks within `streamRadiusChunks` (default 2), **filtered to revealed cells** |
| **Map layers** | camp stock, supply requests, lead claims, footprint heat, district names, map summaries | On `mapRequest`, filtered to revealed cells. Camp/hub status and supply requests are global |

Plus **revealed geometry** (walls of revealed cells) for chunks within `streamRadiusChunks`, and private **touch** data (§6.4).

- Annotations can only be **placed on revealed cells**, so placing one never leaks a hidden cell.
- **Fog invariant (tested, §17):** no message to a client ever references an unrevealed cell, except that client's own touch data; and no player's position is sent to a client outside that client's visible set.

---

## 7. Movement

- Continuous first-person movement. Walk speed `walkSpeed` (default 2.5 m/s, about 1.6 s per cell). No sprint at MVP (tunable; ask before adding).
- Pushing a cart: `cartSpeedMultiplier` (default 0.6).
- **Darkness:** if the player's current cell is not illuminated (own lantern, lit bitset, ambient, flare), speed is multiplied by `darkSpeedMultiplier` (default 0.5). Lit corridors become fast highways; commuting through the dark costs either oil or time. Multipliers stack.
- **Client:** sends input state at 20 Hz (move vector, yaw, actions) with sequence numbers; does **client-side prediction**.
- **Server:** simulates movement authoritatively against the true maze (circle-vs-wall-edge collision, player radius 0.4 m), enforces max speed, and sends **authoritative position + last processed input seq** at 10 Hz. The client reconciles (rewind and replay unacknowledged inputs).
- Any client claim that crosses a closed wall, exceeds speed, or teleports is ignored and corrected; repeated violations feed anti-cheat (§12).
- **Fast travel:** instant transfer between **travel nodes** (entrance depots, active camps, gate hubs) **only if the pack holds 0 oil** and the player isn't attached to a cart. Travel nodes must be fuelled and active (§8.3).
  - **Tank hand-back:** on departure, the lantern tank's contents are credited back to the **departure** node (discarded at a depot), ledger reason `tank_return`.
  - **Tank refill:** on arrival, the tank is filled from the **arrival** node's stock up to `lanternTankCap` (free at a depot), ledger reason `tank_refill`. This doesn't count toward the withdrawal limit.
  - Net effect: no oil moves by fast travel; oil burned on the far side really came from the far side's stock.

---

## 8. Oil & Supply Lines (core system)

### 8.1 The rule
**Oil must be physically carried. Fast travel only works empty-handed.** The deeper the frontier, the longer the supply chain.

### 8.2 Player oil
| Slot | Capacity (default) | Notes |
|---|---|---|
| **Lantern tank** | 10 | Burns `lanternBurnPerMin(ring)` (default 1.0/min) while lit. Refills from pack automatically. Handed back on fast-travel departure, refilled from the arrival node (§7). Can't be deposited or handed off. |
| **Pack** | 20 | Carried supply. Must be **0** to fast-travel. |

About 30 minutes of exploration per load at defaults: enough for a meaningful trip, and short enough that supply lines matter.

### 8.3 Placed lanterns, camps, depots, hubs
**Placed lantern**
- Cost: `lanternPlaceCost` (default 5 oil). Placed on a cell; lights cells within `placedLanternRadius` (default 4) with LOS.
- Must be within `campServiceRadius` (default 32 cells, Euclidean) of an **active camp**, which serves it. Upkeep `lanternUpkeepPerHour` (default 0.1) is drawn from that camp.
- If its camp runs dry, the lantern **goes out**. Its cells stay revealed (on the map) but are no longer lit.
- In a **settled** ring (§8.9) lanterns are permanent: no camp, no upkeep, never go out.

**Camp**
- Build cost: `campBuildCost` (default 50 oil, may be pooled by several players over time as a "construction site").
- Has an **oil stockpile** (cap `campCapacity`, default 1000), visible on the shared map with a fill gauge.
- Upkeep: `campUpkeepPerHour` (default 1.0) plus served lantern upkeep.
- **Active** while stock > 0 → it's a fast-travel node and its lanterns are lit. **Dry** at 0 → not a travel node, its lanterns go out, and the map shows that area un-glowing. Refuelling reactivates it.
- Minimum spacing between camps: `campMinSpacing` (default 48 cells).
- Players can **deposit** freely and **withdraw** up to `campWithdrawLimitPerHour` per player per camp per rolling hour. The base (default 20) is never below `packCap`, and scales linearly with trust up to `campWithdrawTrustMaxMultiplier` × base (default 5×, i.e. 100/h).
- **Delivery withdrawals** (§8.7) don't count toward the hourly limit. Every transaction goes to the `camp_ledger`.
- Camp UI: stock, upkeep rate, estimated time to dry, recent contributors, supply request status, expedition board (§9.9).

**Entrance depot**: endless oil, always active, at Ring 1's entrances.

**Gate hub**: auto-created on the arrival side of a gate when it's discovered. Behaves like a camp with a **one-off stockpile** (`hubInitialStock`, default 300) and normal upkeep.

### 8.4 Caches
- Cache spots (§5.6) materialise on first reveal of their chunk (§5.9) with contents rolled from the ring's cache table: oil `cacheOilMin..cacheOilMax` (default 20..60), plus a chance of consumables (periscope, flares).
- Claimed by the first player to interact. Contents go into the pack, overflow stays in the cache. Empty caches are marked automatically on the map.

### 8.5 Carts
- Spawn/buy at depots and camps for `cartCost` (default 10 oil). Capacity `cartCapacity` (default 200).
- Pushed by one player at reduced speed, and **cannot pass narrow doors** (§5.6). Narrow doors sit on the chunk-level tree, so the only way round one is a chunk-level loop: haulers and builders open **coarse lever doors** to create cart routes, which the map highlights once known. Until then, oil crosses a narrow door by hand (unload, carry, hand-off).
- Carts are physical entities that persist where parked. Any player can push a parked cart, and contents can be withdrawn under the same per-hour limit as camps to prevent theft. Loading a cart from a camp is a normal or delivery withdrawal. Owner and contents are logged.
- Can't be fast-travelled. An abandoned cart becomes "salvageable" after `cartAbandonHours` (default 72).

### 8.6 Hand-offs
- A player can offer oil from their pack to an adjacent player, who accepts. This enables relay chains through narrow sections.

### 8.7 Supply requests
- Camps automatically post a **supply request** when estimated time-to-dry falls below `supplyRequestHours` (default 24). Requests show on the map and the camp board. Deliveries are tracked and credited to haulers (stats/chronicle).
- **Delivery withdrawals:** at any camp, a player can accept an open request for another camp and withdraw up to `min(free pack/cart capacity, request remaining)` **outside** the hourly limit. That oil is tagged for the destination. Depositing it at the destination fulfils the request and credits the hauler. If it isn't delivered within `deliveryWindowHours` (default 6), the shortfall is recorded, trust drops proportionally, and repeated shortfalls raise a behaviour flag.

### 8.8 Oil as a pacing lever
The server can tune `lanternBurnPerMin(ring)` live and `cacheDensityPermille(ring)` for unrevealed chunks (§10.5).

### 8.9 Settled rings
- When ring *k+1* opens (its first arrival gate is discovered), ring *k* becomes **settled** (§10.1).
- Every placed lantern in a settled ring becomes **permanent**: it detaches from its camp, needs no upkeep and never goes out. Lanterns placed later in a settled ring are permanent from the start.
- Camps, hubs and carts in a settled ring keep working normally.
- Result: the glow left behind is kept, and the map fills with light from the outside in as promised (§9.1).
- **Open question (§18 Q13):** how deep supply chains should run across rings.

---

## 9. Collaboration Tools

All player-authored text (notes, signposts, names) goes through a **profanity/abuse filter** and is **reportable**. All placement actions are rate-limited (§15).

### 9.1 Shared map
- Every revealed cell, for everyone. **Explored cells** are drawn as dim ink lines. **Lit cells** glow warm gold. Over months the map visibly fills with light from the outside in. *This is the signature visual of the game.*
- Layers (toggleable): markers, camps & stock levels, lanterns, supply requests, expedition claims, footprint heat, chalk, cart-friendly routes, district names, gates.

### 9.2 Markers
- Placed on the map **or** in-world (appears as a small flag or pennant). Types: `dead_end`, `route`, `warning`, `cache_empty`, `gate_rumour`, `question`, `camp_site`.
- Others can **confirm** or **dispute**. Displayed weight = trust-weighted net score. Markers with no confirmations fade after `markerFadeDays` (default 7). Net-negative markers are hidden.

### 9.3 Footprints
- Server aggregates traversal counts per cell over a rolling 24 h window (bucketed hourly). Clients receive heat for revealed cells near them: in-world as worn floor and faint footprints, on the map as a heat layer.

### 9.4 Chalk
- Draw on a specific **wall face**: shapes `arrow_l/r/u/d`, `x`, `circle`, `tick`, digits `0–9`. Free. Rate limit 30/hour. Max `chalkPerPlayer` active (default 200); the oldest fades when exceeded. Visible to everyone in-world and as tiny glyphs on the map at high zoom.

### 9.5 Thread
- Personal breadcrumb: unspools behind you and is visible **only to you** (in-world line on the floor and a map overlay). Expires after 24 h. Toggle on/off.

### 9.6 Periscope
- Rare consumable from caches. Use: for `periscopeSeconds` (default 5), visibility is computed from a raised viewpoint that **ignores walls** within `periscopeRadius` (default 10), lit as if by your lantern. Cells seen **are** added to the shared map.

### 9.7 Flares
- Crafted at a camp for `flareCost` (default 3 oil) or found in caches. Thrown along your aim. Lights `flareRadius` (default 6) for `flareSeconds` (default 60), revealing cells in its light.

### 9.8 Bells
- Placed at a junction cell for `bellCost` (default 10 oil). Anyone can ring it.
- When rung, the server finds all players within `bellPathRange` (default 40 cells) **by path distance through the true maze** (BFS). Each receives a sound event whose **direction is the first step of their path toward the bell**, so sound appears to travel down corridors. This hints at routes without revealing geometry.
- Rate limit per bell: once per 10 s.

### 9.9 Expedition board
- At every camp and hub. The server computes **leads**: open edges from revealed cells into unrevealed cells (the frontier), clustered by proximity.
- Players **claim** a lead (`leadClaimHours`, default 2). Claims show on the map so others pick different branches. Claims expire or are released on completion. Completing a lead (frontier there closed or pushed past) is credited.

### 9.10 Notes
- Short text (max 80 chars) placed on a cell (Dark Souls style). Others **rate** up or down. Net-negative notes are hidden. Rate limit 10/hour.

### 9.11 Shortcuts (lever walls)
- A lever wall (§5.6) shows a visible lever on one side. Pulling it **opens the wall permanently for everyone**, creating a loop that shortens commutes. Recorded in the chronicle with the puller's name.

### 9.12 Signposts
- Placed for `signpostCost` (default 2 oil). Short text (max 60 chars) visible in-world and on the map. Reportable and rateable like notes.

### 9.13 Two-player (twin-plate) doors
- Certain chunk doors (§5.6) are sealed by a heavy door with **a pair of pressure plates on each side**, each within `plateMaxDistanceCells` (default 6) of the door. Both plates of either pair held simultaneously for 3 s → **opens permanently for everyone**. Plates on both sides mean it works whichever way players arrive.
- Plates and the door are visible once revealed. These sit on the spanning tree, so the community must cooperate to pass (or open a coarse lever door around it).
- Standing on a plate automatically raises a `need_partner` ping (§9.17).

### 9.14 Naming rights
- A **district** = one chunk. The first player to reach `districtNamingThreshold` (default 90%) of a chunk's cells revealed *personally* (lit by them) earns the right to name it (filtered, max 30 chars). Names appear on the map.
- **Gate discoverers** get a plaque at the gate and a chronicle entry.

### 9.15 Chronicle
- A global event feed (in-game and on the map screen): gates discovered, shortcuts opened, camps built or gone dry, districts named, milestones (e.g. "1,000,000 cells lit"), pacing hints (§10.5). Stored in `chronicle_events`.

### 9.17 Pings & quick-chat
- **Pings:** contextual markers placed on a revealed cell, with kinds `need_partner`, `help`, `follow_me`, `oil_here`, `lost`. Shown on the HUD (direction + path distance) for players within `pingRadiusCells` (default 64, path distance) and on the map for everyone in the ring for `pingSeconds` (default 300). Rate limit 20/hour.
- **Quick-chat:** a fixed list of phrases (e.g. "Need a partner here", "Thanks!", "Follow me", "Oil at camp", "Dead end"), shown above the speaker's head to players whose visible set includes the speaker. No free text, so nothing to moderate. Rate limit 1 per 3 s.

### 9.16 Anti-griefing for collaboration tools
- Trust score per player (§12.4) weights confirmations and disputes.
- Rate limits on every placement.
- Reports → moderation queue (admin CLI).
- Camp and cart withdrawal limits with ledgers.

---

## 10. Rings & the Pacing Service

### 10.1 Ring lifecycle
```
provisional ──(locked by pacing or by gate discovery)──▶ locked ──(first gate into it discovered)──▶ open ──(next ring opens)──▶ settled
```
- **provisional**: has a seed and default size, but nobody can see it, so it can be resized freely.
- **locked**: size final; generation parameters, gate slots and active gates frozen.
- **open**: reachable by players.
- **settled**: still open and explorable; its lanterns are permanent (§8.9).
- **Invariant: the next ring after the current innermost open ring must always exist** (at least provisional) **so a gate never leads nowhere.** If a gate is discovered while the next ring is provisional, that ring is **locked immediately** with its current sizing.
- When a ring is locked, the service immediately creates the ring after it as **provisional** with default size (until `plannedRingCount` is reached, then the Core).

### 10.2 Key metric
- `newCellsPerDay`: cells added to the shared map per day (all rings), smoothed as a **7-day rolling average**. It captures player count, play time, skill, coordination, and commute drag in one number.
- Also track per-ring: revealed fraction, active players, per-player reveal rates (for sim calibration).

### 10.3 Sizing formula
```
f          = fraction of a ring explored before its first gate is found
             (initially from simulation; afterwards the measured value from previous rings, blended)
targetDays = ringTargetDays (default 21)
growth     = week-over-week trend in newCellsPerDay, clamped to [0.5, 2.0]

ringAreaCells  = newCellsPerDay × targetDays × growth / f
ringAreaChunks = ceil(ringAreaCells / 1024)
```
Clamp `ringAreaChunks` to `[ringMinChunks, ringMaxChunks]` (defaults 64 and 200,000).

**Shape from area:** use a **thickness ratio** `ρ = T / b` so rings keep sensible proportions at any size (a fixed thickness gives absurdly long, thin bands at scale):
```
chunks = (2b)^2 - (2(b - T))^2 = 8bT - 4T^2,   T = ρb   →   b = sqrt(chunks / (8ρ - 4ρ^2))
then T = max(1, round(ρb)),  b = ceil((chunks + 4T^2) / (8T)),  a = b - T   (require a ≥ 1, else T = b - 1)
```
- Start with `ρ = ringThicknessRatio` (default 0.25). Example: 5,000 chunks → b ≈ 54, T ≈ 13 (about 14 km across, 1.7 km thick).
- Prefer `b_new ≤ a_previous` so rings feel like they shrink inward. If not, raise `ρ` in steps up to `ringThicknessRatioMax` (default 0.5); a thicker ring of the same area has a smaller `b`.
- If still impossible, allow the larger `b`: frames are independent, and the world map draws rings as a schematic, not to scale.
- `ρ` never goes below `ringThicknessRatioMin` (default 0.15).

**`f` as a function of shape:** `f` depends strongly on thickness and gate count. The M2.5 sims sweep `ρ`, `gateCount` and ring size and fit `f(ρ, gateCount, chunks)`. The sizing formula uses the fitted function (blended with measured values from previous rings) instead of a single constant.

### 10.4 When to lock
- Nightly (and on demand), compute for the current innermost open ring:
```
expectedCellsToGate = f × ringAreaCells_current
remaining           = max(0, expectedCellsToGate - revealedCells_current)
etaDays             = remaining / newCellsPerDay
```
- If `etaDays < lockLeadDays` (default 7) and the next ring is provisional → **resize with the formula, then lock**.

### 10.5 Live levers (for being too fast or too slow mid-ring)
| Situation | Levers (automatic within guardrails, or manual via CLI) |
|---|---|
| **Too slow** (ETA ≫ target) | Activate a **reserved gate slot** (§5.7) whose gate cell in ring *k* and arrival cell in ring *k+1* are both still **unrevealed** (overlay entry, §5.10), choosing the eligible slot nearest the recent exploration centroid; raise `cacheDensityPermille` for unrevealed chunks; lower `lanternBurnPerMin`; post a chronicle **hint** ("Scouts report a draught from the north-east…" pointing at the nearest gate's quadrant) |
| **Too fast** | Next ring sized larger (automatic via formula); raise `lanternBurnPerMin` modestly; lower cache density for unrevealed chunks |
- Guardrails: burn rate within `[0.5, 2.0]` × default; max 1 automatic extra gate per ring per week; max one hint per 5 days.

### 10.6 Automation & alerts
- Pacing runs as an in-process scheduler (nightly at 03:00 server time, plus hourly ETA check).
- Every decision is written to `pacing_log` and sent to an **alert webhook** (Discord-compatible) with a summary: rate, f, ETA, chosen size, levers pulled.
- **It never waits for a human.** Admins can override via CLI (§14) at any time.
- **Viral spike handling:** if the 1-day rate exceeds 3× the 7-day average, run the lock check immediately and size with the 1-day rate for provisional rings.

### 10.7 Ring themes
- Each ring has a `themeId` chosen from a list **shipped in the client from day one** (art, materials, lighting, audio). The server just assigns it. Examples (placeholders): `1 = overgrown hedge & stone (dusk)`, `2 = old brick (night)`, `3 = cavern (dark, narrow-heavy)`, `4 = flooded halls`, `5 = obsidian (pitch black)`, `core`.
- Per-ring generation params (frozen at lock): `newestBiasPermille`, `narrowPermille`, `leverPermille`, `leverMinTreeDistance`, `coarseLeverPermille`, `platePermille`, `plateMaxDistanceCells`, `gateSlotCount`, `gateCount`.
- Per-ring live params (tunable): `ambientRadiusCells`, `cacheDensityPermille` (unrevealed chunks only), `lanternBurnPerMin`.

---

## 11. Client (Godot 4)

### 11.1 Project structure
```
project.godot   (repo root = res://)
/client
  /autoload    Net.gd (WebSocket + protocol), Session.gd, WorldState.gd, Settings.gd
  /scenes      Main.tscn, Player.tscn, Chunk.tscn, MapScreen.tscn, HUD.tscn, Core.tscn, Tutorial.tscn
  /world       chunk_renderer.gd, wall_builder.gd, entity_spawner.gd, light_manager.gd
  /player      fp_controller.gd, prediction.gd, lantern.gd, interaction.gd, chalk_tool.gd
  /ui          map_screen.gd, hud.gd, camp_panel.gd, radial_menu.gd, chronicle_panel.gd
  /themes      ring_1/, ring_2/, ... (materials, meshes, environment, audio)
  /audio
```

### 11.2 Rendering
- **Renderer:** Forward+ (many dynamic lights from lanterns).
- **Chunks:** stream only revealed geometry within `streamRadiusChunks`. Walls are built with **MultiMeshInstance3D** per chunk (one instance per wall segment, with variants by theme). Floors are one mesh per chunk. Collision uses StaticBody3D per chunk, generated from known walls plus touch geometry.
- **Unrevealed space** renders as darkness/void. Never fake geometry.
- **Lights:** player lantern = OmniLight3D (warm, flicker). Placed lanterns = OmniLight3D with distance culling (max ~32 active nearest). Shadows only on the player lantern.
- **Atmosphere:** WorldEnvironment per ring theme (fog, ambient). The **Lighthouse** stands at the frame origin of every ring: very tall, visible above the walls as a dark silhouette against the sky, so players always know which way is "in". It is **unlit** until ignition (§5.8). During the Kindling its glass glows faintly in proportion to the reservoir level, visible from every ring.
- In-world decals: chalk, footprint wear, markers (pennants), notes (glowing glyph), signposts, plaques.

### 11.3 First-person controller
- CharacterBody3D, mouse look, WASD. Actions: `E` interact, `F` lantern toggle, `M` raise map, `C` chalk radial menu, `Q` throw flare, `T` toggle thread, `Tab` camp/board panel when at a camp.
- Client-side prediction with reconciliation against server corrections (§7). Smooth small corrections and snap large ones.

### 11.4 Map screen (the star)
- Raised as a **hand-held parchment map** (diegetic). Gameplay continues behind it, so you're vulnerable to getting lost, not to enemies (there are none).
- Rendered with per-chunk **ImageTextures** (1 px per cell edge at detail zoom). Explored = ink lines; lit = warm glow with soft bloom; unexplored = blank parchment.
- **Zoom levels:** detail (cells), district (chunks with names), ring overview (per-chunk explored and lit fractions from map summaries), world (all rings as nested schematic bands, showing overall glow progress).
- Overlays per §9.1. Tap or click a marker, camp, or claim for details. Place markers from the map.
- "You are here" arrow plus your thread.

### 11.5 HUD (minimal)
Lantern tank gauge, pack oil, cart status, interact prompts, current district name, compass ring pointing toward the centre.

### 11.6 Audio
Footsteps per surface; lantern hiss; bells with directional cue (§9.8); ambient per ring; distant sounds of other players' activity (abstracted, never positional through walls beyond bell rules).

### 11.7 Steam
GodotSteam for auth tickets, achievements, rich presence ("Ring 2 · Hauling oil to Camp Ember"). Development builds use dev auth.

---

## 12. Anti-Cheat & Anti-Bot

### 12.1 Structural guarantees
- Server-authoritative movement with speed and wall validation (§7).
- Fog of war on the server; unseen geometry, entities, and players never sent (§6.5).
- All actions validated (costs, ranges, rate limits) server-side.

### 12.2 Account cost
- Paid Steam game; **Steam session tickets verified server-side** via the Steamworks Web API (`ISteamUserAuth/AuthenticateUserTicket`). One Steam account = one player.

### 12.3 Behaviour detection
Collect per-session metrics: continuous session length, input timing variance, path efficiency, hesitation at junctions, reveal rate vs. population distribution, action cadence, delivery shortfalls. Flag outliers. Flagged accounts get **reduced trust** (less weight on votes and confirmations, lower withdrawal limits) and go to the admin review queue. There's **no covert speed reduction**: false positives would hit paying players, and a community that measures everything would notice. Bans only after human review.

### 12.4 Trust score
Starts low and grows with account age, confirmed markers, deliveries, and lack of reports. Weights marker confirmations, note ratings, and moderation priority.

### 12.5 Sim bots are first-class
The `/sim` bots go through exactly the same validation as humans, which doubles as the anti-cheat regression test.

---

## 13. Network Protocol

- WebSocket, **JSON** at MVP (msgpack later behind a flag). Every message `{ "t": "<type>", ...payload }`. Validate all inbound messages with zod. Unknown or invalid → drop + metric.
- Keep the full reference in `/shared/protocol.md`; this is the starting set.

**Client → Server**
| Type | Payload |
|---|---|
| `hello` | `{ authKind: "dev"|"steam", token, clientVersion }` |
| `input` | `{ seq, moveX, moveY, yaw, pitch, dt }` (20 Hz) |
| `lantern` | `{ on: boolean }` |
| `interact` | `{ targetId }` (cache, lever, camp, cart, bell, plate, hub) |
| `fastTravel` | `{ nodeId }` |
| `campDeposit` / `campWithdraw` | `{ campId, amount }` |
| `campBuild` | `{ cell }` (start/contribute to construction site) |
| `placeLantern` / `placeBell` / `placeSignpost` | `{ cell, text? }` |
| `chalk` | `{ cell, face: "N"|"E"|"S"|"W", glyph }` |
| `marker` | `{ ring, cell, kind }` |
| `markerVote` | `{ markerId, vote: 1|-1 }` |
| `note` / `noteVote` | `{ cell, text }` / `{ noteId, vote }` |
| `throwFlare` / `usePeriscope` | `{}` |
| `cartAttach` / `cartDetach` / `cartLoad` / `cartUnload` | `{ cartId, amount? }` |
| `handOffOffer` / `handOffAccept` | `{ toPlayerId, amount }` / `{ offerId }` |
| `leadClaim` / `leadRelease` | `{ leadId }` |
| `nameDistrict` | `{ ring, cx, cy, name }` |
| `mapRequest` | `{ ring, zoom, rect }` |
| `report` | `{ targetKind, targetId, reason }` |
| `ping` | `{ cell, kind }` |
| `quickChat` | `{ phraseId }` |
| `deliveryAccept` | `{ requestId, fromCampId, amount }` |

**Server → Client**
| Type | Payload |
|---|---|
| `welcome` | player state, world meta (rings list, themes, travel nodes), server time |
| `state` | `{ ackSeq, pos, vel, lanternOil, packOil, cartId? }` (10 Hz) |
| `reveal` | `{ ring, cx, cy, cells: [idx...], walls: bytes }`: newly revealed cells + wall bits |
| `chunkSync` | full revealed geometry for a chunk entering stream radius |
| `touch` | private walls around the player (darkness collision) |
| `lit` | lit-cell deltas for streamed chunks |
| `entities` | spawn/update/despawn for visible entities (players, carts, lanterns, bells, notes, signposts, chalk, markers, caches, levers, plates, camps) |
| `sound` | `{ kind: "bell", dir: [x,y], intensity }` |
| `mapSummary` | per-chunk explored/lit fractions for a rect |
| `campStatus` | stock, upkeep, ETA, requests, claims |
| `chronicle` | events |
| `ping` | `{ id, ring, cell, kind, fromPlayerId, dir?, pathDist?, expiresAt }` |
| `quickChat` | `{ playerId, phraseId }` (only if the speaker is in your visible set) |
| `notice` / `error` | user-facing messages, rejected-action reasons |

---

## 14. Persistence (PostgreSQL)

```sql
-- World & rings
worlds(id PK, seed INT NOT NULL, gen_version INT NOT NULL, created_at)
rings(id PK, world_id FK, ring_index INT, seed BIGINT, gen_version INT,
      status TEXT CHECK (status IN ('provisional','locked','open','settled')),
      outer_half INT, inner_half INT, theme_id TEXT, gen_params JSONB, live_params JSONB,
      created_at, locked_at, opened_at, settled_at, UNIQUE(world_id, ring_index))

-- Shared map
chunk_reveal(ring_id FK, cx INT, cy INT, bits BYTEA /*128 bytes*/, revealed_count INT, updated_at,
             PRIMARY KEY(ring_id, cx, cy))
chunk_materialised(ring_id, cx, cy, cache JSONB, materialised_at, PRIMARY KEY(ring_id,cx,cy))
cell_reveal_credit(ring_id, cx, cy, player_id, count INT, PRIMARY KEY(ring_id,cx,cy,player_id)) -- naming rights

-- Players
players(id PK, steam_id TEXT UNIQUE, display_name, created_at, trust REAL, flags JSONB, banned_at)
player_state(player_id PK FK, ring_id, x REAL, y REAL, yaw REAL, lantern_oil REAL, pack_oil REAL,
             lantern_on BOOL, cart_id, updated_at)
player_stats(player_id PK, cells_revealed BIGINT, oil_delivered BIGINT, gates_found INT, ...)

-- Supply
camps(id PK, ring_id, cell_x, cell_y, name, stock REAL, status TEXT, built_by, created_at, kind TEXT /*camp|depot|hub*/)
camp_ledger(id PK, camp_id, player_id, delta REAL, reason TEXT /*deposit|withdraw|delivery_withdraw|delivery_deposit|tank_return|tank_refill|upkeep|build*/, at)
lanterns(id PK, ring_id, cell_x, cell_y, camp_id NULL, permanent BOOL DEFAULT false, placed_by, placed_at)
deliveries(id PK, request_id, player_id, from_camp_id, to_camp_id, amount REAL, delivered REAL DEFAULT 0,
           created_at, due_at, status TEXT /*active|delivered|shortfall*/)
carts(id PK, ring_id, x REAL, y REAL, oil REAL, owner_id, pushed_by, updated_at)
cache_claims(ring_id, cx, cy, claimed_by, claimed_at, remaining JSONB, PRIMARY KEY(ring_id,cx,cy))
supply_requests(id PK, camp_id, created_at, fulfilled_at)

-- Collaboration
markers(id PK, ring_id, cell_x, cell_y, kind, author_id, created_at, score REAL, status TEXT)
marker_votes(marker_id, player_id, vote SMALLINT, PRIMARY KEY(marker_id, player_id))
chalk(id PK, ring_id, cell_x, cell_y, face CHAR(1), glyph TEXT, author_id, created_at)
notes(id PK, ring_id, cell_x, cell_y, text, author_id, created_at, score REAL, status TEXT)
note_votes(note_id, player_id, vote SMALLINT, PRIMARY KEY(note_id, player_id))
signposts(id PK, ring_id, cell_x, cell_y, text, author_id, created_at, score REAL, status TEXT)
bells(id PK, ring_id, cell_x, cell_y, placed_by, created_at)
opened_walls(ring_id, cell_x, cell_y, edge CHAR(1) /*E|S, owned-edge form*/,
             kind TEXT /*lever|coarse_lever|plate|gate|arrival*/, opened_by NULL, opened_at,
             PRIMARY KEY(ring_id,cell_x,cell_y,edge))   -- append-only overlay (§5.10)
gates(id PK, ring_id, slot_index INT, t_fix BIGINT, t REAL /*display*/, cell_x, cell_y,
      active BOOL, extra BOOL /*activated by pacing*/, activated_at, discovered_by, discovered_at,
      UNIQUE(ring_id, slot_index))
pings(id PK, ring_id, cell_x, cell_y, kind TEXT, player_id, created_at, expires_at)  -- or in-memory only
district_names(ring_id, cx, cy, name, named_by, named_at, PRIMARY KEY(ring_id,cx,cy))
lead_claims(id PK, ring_id, lead_key TEXT, player_id, claimed_at, expires_at, status TEXT)
threads(player_id, points BYTEA, updated_at) -- or in-memory only with 24h TTL
footprints_hourly(ring_id, cx, cy, hour_bucket TIMESTAMPTZ, counts BYTEA, PRIMARY KEY(...))

-- Finale
lighthouse(world_id PK, oil_required REAL, oil_stored REAL, kindling_started_at, ignition_scheduled_at,
           ignited_at, first_arrival_player_id, first_arrival_at)
lighthouse_contributions(player_id PK, oil REAL, last_at)
-- worlds gains: illuminated BOOL DEFAULT false

-- Meta
chronicle_events(id PK, at, kind, payload JSONB)
exploration_daily(day DATE, ring_id, new_cells BIGINT, active_players INT, PRIMARY KEY(day, ring_id))
pacing_log(id PK, at, decision JSONB)
reports(id PK, reporter_id, target_kind, target_id, reason, at, status)
behaviour_flags(player_id, kind, score REAL, at)
```
Use migrations (e.g. `node-pg-migrate` or plain SQL files with a tiny runner).

---

## 15. Tunables (defaults) — `server/src/config/game.ts`

| Key | Default | Notes |
|---|---|---|
| `cellSizeM` | 4 | Shared with client via `welcome` |
| `wallHeightM` | 4.5 | |
| `chunkSize` | 32 | Cells per side (don't change after launch) |
| `tickHz` / `stateHz` / `visibilityHz` | 20 / 10 / 5 | |
| `walkSpeed` | 2.5 m/s | |
| `cartSpeedMultiplier` | 0.6 | |
| `darkSpeedMultiplier` | 0.5 | Unlit cells (§7) |
| `playerRadiusM` | 0.4 | |
| `lanternRadiusCells` | 6 | |
| `ambientRadiusCells` | per ring: R1=2, else 0 | |
| `lanternTankCap` / `packCap` | 10 / 20 | |
| `lanternBurnPerMin` | per ring, 1.0 | Pacing lever |
| `lanternPlaceCost` / `placedLanternRadius` | 5 / 4 | |
| `lanternUpkeepPerHour` | 0.1 | |
| `campBuildCost` / `campCapacity` | 50 / 1000 | |
| `campUpkeepPerHour` | 1.0 | |
| `campServiceRadius` / `campMinSpacing` | 32 / 48 cells | |
| `campWithdrawLimitPerHour` | 20 | Base; never below `packCap` |
| `campWithdrawTrustMaxMultiplier` | 5 | Limit scales with trust up to this × base |
| `deliveryWindowHours` | 6 | Delivery withdrawals (§8.7) |
| `hubInitialStock` | 300 | |
| `cacheDensityPermille` | per ring, 250 | Pacing lever |
| `cacheOilMin` / `cacheOilMax` | 20 / 60 | |
| `cartCost` / `cartCapacity` / `cartAbandonHours` | 10 / 200 / 72 | |
| `flareCost` / `flareRadius` / `flareSeconds` | 3 / 6 / 60 | |
| `periscopeSeconds` / `periscopeRadius` | 5 / 10 | |
| `bellCost` / `bellPathRange` | 10 / 40 | |
| `signpostCost` | 2 | |
| `narrowPermille` | per ring, R1=0, else 150 | Tree coarse doors only |
| `leverPermille` / `leverMinTreeDistance` | 15 / 40 | In-chunk lever walls |
| `coarseLeverPermille` | 200 | Non-tree coarse edges |
| `platePermille` / `plateMinRing` / `plateMaxDistanceCells` | 80 / 3 / 6 | |
| `newestBiasPermille` | per ring, 750 | Growing Tree |
| `gateCount` / `gateSlotCount` / `entranceCount` | 5 / 12 / 4 | |
| `plannedRingCount` | 5 | + core |
| `ringTargetDays` | 21 | |
| `lockLeadDays` | 7 | |
| `ringMinChunks` / `ringMaxChunks` | 64 / 200000 | |
| `ringThicknessRatio` / `ringThicknessRatioMin` / `ringThicknessRatioMax` | 0.25 / 0.15 / 0.5 | ρ = T/b (§10.3) |
| `fInitial` | 0.4 | Replace with fitted `f(ρ, gateCount, chunks)` from sims |
| `kindlingTargetDays` / `kindlingFactor` | 10 / 0.8 | Lighthouse sizing |
| `lighthouseOilMin` / `lighthouseOilMax` | 5000 / 5000000 | |
| `ignitionDelayMinutes` / `ignitionWaveSeconds` | 30 / 300 | |
| `sliceRingShape` / `sliceLighthouseOil` | outer 4, inner 2 / 2000 | Vertical slice only (§16.0) |
| `sliceRingGenParams` | all features on (narrow 150, plates 80, ...) | Vertical slice only (§16.0) |
| `markerFadeDays` | 7 | |
| `chalkPerPlayer` | 200 | |
| `leadClaimHours` | 2 | |
| `supplyRequestHours` | 24 | |
| `districtNamingThreshold` | 0.9 | |
| `streamRadiusChunks` | 2 | |
| `chunkCacheSize` | 20000 | |
| `losCacheSize` | 200000 | Per-cell LOS masks (§6.2) |
| `visibilityWorkers` | cores − 1 | |
| `pingRadiusCells` / `pingSeconds` | 64 / 300 | §9.17 |
| `persistIntervalSec` | 5 | |
| Rate limits | chalk 30/h, notes 10/h, markers 30/h, signposts 10/h, votes 120/h, pings 20/h, quick-chat 1 per 3 s | |

---

## 16. Milestones & Acceptance Criteria

### 16.0 Vertical slice (current plan, decided 2026-10-09)
**Goal:** answer "is this fun together?" with **every game feature** in place, but in **one ring plus the Core** instead of the full expanse. Milestones M0–M1 are done. The slice then runs S1–S8 below. The full-scale milestones (M7 multi-ring pacing, M8 Steam & anti-cheat, the rest of M9, M10) follow the slice.

**World for the slice**
- `plannedRingCount = 1`: one ring (Ring 1) whose active gates lead straight to the **Core**. Same code paths as the full game; the world is just one ring deep.
- **Ring 1 enables every generation feature** (narrow doors, coarse lever doors, twin-plate doors, levers), overriding the normal "ring ≥ 2/3" defaults: `sliceRingGenParams`.
- Ring size is a fixed tunable, `sliceRingShape` (default `outerHalf 4, innerHalf 2` = 48 chunks, about 49k cells; enlarge as playtest groups grow). No pacing service; reserved gate slots stay unused.
- Lighthouse oil target is a fixed tunable, `sliceLighthouseOil` (default 2,000), instead of being sized by pacing.

**In the slice:** server core, Godot client, shared map, the full oil & supply-line system (lantern/pack, depots, camps, placed lanterns, withdraw limits and delivery withdrawals, fast travel with tank hand-back, darkness speed, caches, carts with narrow and coarse lever doors, hand-offs, supply requests, gate hubs), all collaboration tools (§9, including the text filter, reports, pings and quick-chat), gate discovery, the Core, the Kindling, ignition, the Wall of Names, the tutorial antechamber, and a **proper Ring 1 theme** (hedge & stone at dusk) plus the Core and Lighthouse.

**Out of the slice:** rings ≥ 2, the pacing service (§10.2–10.6), settled rings (§8.9), depot lag (§18 Q13), other ring themes, Steam login and achievements (dev login only), behaviour detection (§12.3). Trust (§12.4) is simplified to account age plus confirmed contributions. The core anti-cheat guarantees (server-authoritative movement, fog invariant, validation, rate limits) **are** in.

**Art direction (decided 2026-10-09):** proper 3D, atmospheric and **almost horror**: dense fog that the lanterns visibly **pierce** (volumetric fog + light shafts), deep darkness outside the light, warm amber flame light against cold blue-grey dusk. **Semi-realistic but "gamified"**: believable materials (weathered stone, damp hedge, aged brass, soot-stained glass) with readable, slightly exaggerated shapes and silhouettes, chunky proportions, and strong warm/cold contrast so gameplay information (lit vs unlit, levers, plates, gates) always reads at a glance. Not photoreal, not cartoon.

**Art production:** assets are **modelled in Blender** (via the Blender MCP connection), with procedural or CC0 textures (e.g. Poly Haven, ambientCG), and exported as **glTF** into `client/assets/`. Every external texture/asset is recorded in `client/ASSETS.md` with source and licence. Blender source files live in `art/` (with a `.gdignore`). A **look-dev scene** in Godot (fog, lantern light, a few wall modules) is built early, so the mood is settled before the slice's gameplay milestones lean on it.

**Slice milestones** (the M-numbers show which full-game acceptance criteria apply)
| # | Milestone | Scope |
|---|---|---|
| S1 | Server core | M2 in full (one ring), including the CPU budget and fog invariant |
| S2 | Test bots | M2.5's bot clients and runner, used as the integration-test harness (the `f` sweep waits for multi-ring) |
| S3 | Godot client | M3: connect, FP controller with prediction, chunk rendering, lantern light, darkness, touch collision (placeholder art) |
| S4 | Shared map | M4 |
| S5 | Oil & supply lines | M5, minus settled rings |
| S6 | Collaboration tools | M6 |
| S7 | Gates, Core & finale | Gate discovery → gate hub in the Core → the Kindling, ignition, Wall of Names, first-arrival plaque (M8.5 criteria, with bots on a small ring) |
| S8 | Look, sound & onboarding | Ring 1 theme, Core & Lighthouse art, audio, tutorial antechamber, settings & accessibility basics, a hosted playtest server |

Stop and report at the end of each S-milestone.

### M0 — Scaffold
- Monorepo per §4.2 (Godot project at the root, `.gdignore` in every non-Godot folder), `docker-compose.yml` with Postgres, TS config, lint (eslint + prettier), vitest, CI (GitHub Actions) running tests on push. Godot project opens without importing anything from the TS folders.
- ✅ `npm test` passes in CI; `docker compose up` gives a working DB; migrations run (tested in-process against PGlite, and in CI against a real Postgres service).

### M1 — Maze generation library (server/src/maze)
- hash32, mulberry32 (integer draws), coarse Kruskal, Growing Tree chunk maze, ring geometry and shape-from-area (§10.3), doors, gate slots and edge mapping (§5.7), entrances/arrivals, deterministic features (§5.6, including coarse lever doors and both-side plate pairs), opening overlay (§5.10).
- Debug tools: `/tools/render-ring` → PNG of a whole small ring (walls, gates, reserved slots, entrances, levers, coarse lever doors, narrow doors, plates, cache spots in colours) and an ASCII printer for one chunk.
- ✅ Tests: determinism golden vectors; **perfect-maze property** of the base layout for random small rings (cells − 1 = open edges; single connected component; BFS from any entrance reaches every cell and every gate); boundary walls closed except openings; gate `tFix` → edge mapping covers each boundary edge exactly once and round-trips between two rings of different sizes; opening a lever adds exactly one loop; no `Math.random` in `/maze` (lint rule).

> **Stop here and report before M2.**

### M2 — Server core
- WebSocket server, dev auth, sessions, spawn at entrance depot, authoritative movement + collision + speed validation, visibility (DDA LOS + light), reveal to shared map, touch geometry, chunk streaming, persistence (write-behind), interest management.
- ✅ Two dev clients (scripted) in the same area see each other only with line of sight; reveals persist across server restart; wall-crossing and speed hacks are rejected; fog invariant (§6.5) holds over a scripted session.
- ✅ **CPU budget:** 2,000 simulated players moving in one process keep visibility under 40% of one core (across the worker pool) and the tick under 10 ms at p99. If this fails, fix it before M3.

### M2.5 — Sim explorer bots (/sim)
- Headless bot clients over the real protocol. Strategies: `randomDFS`, `frontierSeeker` (uses shared map, picks nearest unclaimed lead), `hauler` (moves oil camp to camp, once M5 exists).
- Experiment runner: N bots × duration on a test ring → reports new cells/hour/bot, **f** (fraction explored when the first gate is found) over many seeds, server CPU/memory.
- ✅ Run 200 bots on a local server for 30 min without errors; produce `f` estimates with confidence intervals over a sweep of `ρ ∈ {0.15, 0.25, 0.35, 0.5}`, `gateCount ∈ {3, 5, 8}` and several sizes, and fit `f(ρ, gateCount, chunks)`.
- ✅ Oil economy report: with `hauler` bots (after M5), measure frontier exploration minutes per oil delivered, and confirm frontier camps need real supply (tank hand-back rule, §7).

### M3 — Godot client (deliberately ugly)
- Connect, dev login, render revealed chunks (MultiMesh walls), FP controller with prediction/reconciliation, lantern light, darkness, touch collision.
- ✅ Walk a ring in first person; geometry appears exactly as light reveals it; corrections are smooth.

### M4 — The shared map
- Map screen with zoom levels, explored ink vs. lit glow, "you are here", world-level nested-ring view.
- ✅ Watching sim bots explore, the map visibly fills in live.

### M5 — Oil & supply lines
- Lantern tank/pack, burn, depots, placed lanterns, camps (build, stock, upkeep, dry state), trust-scaled withdraw limits + ledger, delivery withdrawals, fast travel (empty pack only, tank hand-back/refill), darkness speed, caches (materialise on reveal), carts + narrow doors + coarse lever doors, hand-offs, supply requests, hubs, settled-ring permanent lanterns.
- ✅ Running dry turns lanterns off and greys the map glow; refuelling restores it; fast travel refused with oil in pack; fast travel moves no oil (ledger sums to zero apart from burn); carts blocked at narrow doors and pass once a coarse lever loop is open; settling a ring makes its lanterns permanent.

### M6 — Collaboration tools
- Markers (+votes, fading), footprints, chalk, thread, notes, signposts, bells (path-direction audio), flares, periscopes, expedition board/leads, lever shortcuts, twin-plate doors (both sides), pings & quick-chat, naming rights, chronicle, text filter + reports.
- ✅ Each tool has an integration test via sim bots; two bots can open a twin-plate door from either side, with the `need_partner` ping reaching the second bot; lever opening creates a loop visible to all.

### M7 — Rings, gates & pacing
- Ring lifecycle, gate discovery → instant open → hub creation → previous ring settled → next ring locked → following ring provisional. Pacing service (metrics, sizing with thickness ratio and fitted `f`, lock timing, levers incl. reserved gate slot activation, guardrails, viral spike handling), alert webhook, admin CLI (status, overrides, activate gate slot, set levers, moderation queue, broadcast to chronicle).
- ✅ Simulated multi-ring run (accelerated clock) where bot counts change 10× mid-run and ring durations stay within ±30% of target.

### M8 — Steam & anti-cheat
- GodotSteam integration, server-side ticket verification, behaviour metrics, trust reduction for flagged accounts, trust scores, admin review.
- ✅ Non-Steam clients rejected in production mode; synthetic bot behaviour gets flagged and lands in the review queue with reduced trust.

### M8.5 — The Lighthouse finale
- Core scene and hubs, lighthouse reservoir and deposits, Kindling progress (in-world glow, map, HUD banner, chronicle), sizing from oil-delivery rate, ignition scheduling and broadcast, outward light wave, world `illuminated` state (everything revealed and lit), Wall of Names generation and rendering, lantern-room view, first-arrival plaque.
- ✅ Accelerated-clock sim run reaches the core, fills the lighthouse with bots hauling oil, ignites on schedule, every client receives the sequence, the map is fully gold afterwards, and every contributing bot appears on the Wall of Names.

### M9 — Content & polish
- Ring themes 1–5 + core scene art, Lighthouse model (cold, kindling-glow and lit states), audio, tutorial (hand-authored antechamber teaching lantern, oil, map, chalk, markers), rich presence, achievements, settings, accessibility (FOV, motion, colour-blind map palette).

### M10 — Load & launch readiness
- 2,000-bot soak test, msgpack switch, DB indexes and query review, backups, monitoring dashboards, runbook.

---

## 17. Testing Strategy
- **Unit:** maze gen, hashing, geometry maths, sizing formula, oil accounting, rate limiters.
- **Property-based (fast-check):** perfect-maze invariants, gate mapping, ring membership, visibility never returns cells behind walls.
- **Golden:** generation output hashes per seed/version.
- **Integration:** sim bots through the real protocol for every gameplay feature.
- **Security tests:** fog invariant (§6.5: no message references an unrevealed cell except the recipient's own touch data; no player position outside the recipient's visible set), speed/teleport rejection, rate limits, withdrawal limits, fast travel moves no oil.
- **Performance:** visibility/tick CPU budget benchmark (M2) runs in CI on a reduced player count and fails on large regressions.
- **Pacing simulation:** accelerated-clock runs with changing bot populations.

---

## 18. Open Questions (ask before deciding)
1. **Game name** (Project Lantern is a placeholder).
2. ~~What is at the centre?~~ **Decided: the Lighthouse (§5.8).** Still open: the first-arrival gift beyond the plaque, and whether to build the lore fragments and Season 2 horizon hint.
3. **Number of rings** and target total duration (default 5 rings × ~3 weeks).
4. **Gate keys?** Should later rings require collecting keys/fragments to open gates (reserved `gateKeyRequirement`)?
5. **Price point** and whether there's any monetisation beyond purchase (default: one-off purchase, no microtransactions).
6. **After ignition:** the illuminated world stays explorable by default. How long does it stay up, and does Season 2 (a new seed, perhaps the maze on the horizon) follow?
7. **Entrances:** 4 by default; is that right for the community feel?
8. **Player avatars & identity:** how do other players look; are names shown above heads?
9. **Moderation resourcing** for text content (notes, signposts, district names).
10. **Sprint:** none by default; confirm.
11. **Tutorial:** hand-authored antechamber (default) or skipped?
12. **Late joiners:** default is they start at the entrances and fast-travel to any active camp/hub. Confirm. Also: what does a month-3 buyer do that isn't just commuting?
13. **Supply-chain depth across rings.** As specified, oil for ring 5 is hauled from the Ring 1 depots through every ring's hubs, which may be far too long. Proposed default: **depots lag one ring**. When ring *k+1* opens, the hubs at ring *k*'s arrival gates become endless depots, so supply chains span about two rings. Confirm before M7.
14. **Free-text chat:** none at MVP (pings + quick-chat, §9.17). Revisit after playtests? (Moderation cost, §18 Q9.)

---

## 19. Glossary
- **Cell / Chunk / Ring / Core**: see §5.1, §5.8.
- **Revealed**: on the shared map for everyone (requires light).
- **Lit**: currently illuminated by a fuelled lantern/camp/flare; glows on the map.
- **Touch geometry**: private, unmapped walls around a player for collision in darkness.
- **Travel node**: depot, active camp, or gate hub.
- **Lead**: a frontier branch on the expedition board.
- **f**: fraction of a ring explored before its first gate is found.
- **Materialise**: write generated-but-tunable content to the DB on first reveal so it never changes afterwards.
- **Gate slot**: one of `gateSlotCount` fixed positions on a ring's inner boundary; `gateCount` are active at lock, the rest reserved (§5.7).
- **Opening overlay**: the append-only set of walls opened after generation (§5.10).
- **Settled ring**: an open ring whose next ring has opened; its lanterns are permanent (§8.9).
- **ρ (rho)**: ring thickness ratio `T / b` (§10.3).
