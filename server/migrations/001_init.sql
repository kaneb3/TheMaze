-- Initial schema (spec §14, v2). Oil amounts use DOUBLE PRECISION so ledgers sum exactly enough.

-- World & rings ---------------------------------------------------------------------------------
CREATE TABLE worlds (
  id           BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  seed         BIGINT NOT NULL CHECK (seed >= 0 AND seed <= 4294967295),
  gen_version  INT NOT NULL,
  illuminated  BOOLEAN NOT NULL DEFAULT false,
  created_at   TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE rings (
  id           BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  world_id     BIGINT NOT NULL REFERENCES worlds(id),
  ring_index   INT NOT NULL CHECK (ring_index >= 1),
  seed         BIGINT NOT NULL CHECK (seed >= 0 AND seed <= 4294967295),
  gen_version  INT NOT NULL,
  status       TEXT NOT NULL CHECK (status IN ('provisional', 'locked', 'open', 'settled')),
  outer_half   INT NOT NULL,
  inner_half   INT NOT NULL,
  theme_id     TEXT NOT NULL,
  gen_params   JSONB NOT NULL,
  live_params  JSONB NOT NULL,
  created_at   TIMESTAMPTZ NOT NULL DEFAULT now(),
  locked_at    TIMESTAMPTZ,
  opened_at    TIMESTAMPTZ,
  settled_at   TIMESTAMPTZ,
  UNIQUE (world_id, ring_index),
  CHECK (inner_half >= 1 AND outer_half > inner_half)
);

-- Players ---------------------------------------------------------------------------------------
CREATE TABLE players (
  id            BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  steam_id      TEXT UNIQUE,
  display_name  TEXT NOT NULL,
  created_at    TIMESTAMPTZ NOT NULL DEFAULT now(),
  trust         REAL NOT NULL DEFAULT 0.1,
  flags         JSONB NOT NULL DEFAULT '{}'::jsonb,
  banned_at     TIMESTAMPTZ
);

CREATE TABLE player_stats (
  player_id           BIGINT PRIMARY KEY REFERENCES players(id),
  cells_revealed      BIGINT NOT NULL DEFAULT 0,
  oil_delivered       DOUBLE PRECISION NOT NULL DEFAULT 0,
  gates_found         INT NOT NULL DEFAULT 0,
  shortcuts_opened    INT NOT NULL DEFAULT 0,
  camps_built         INT NOT NULL DEFAULT 0,
  lighthouse_oil      DOUBLE PRECISION NOT NULL DEFAULT 0,
  delivery_shortfall  DOUBLE PRECISION NOT NULL DEFAULT 0
);

-- Shared map ------------------------------------------------------------------------------------
CREATE TABLE chunk_reveal (
  ring_id         BIGINT NOT NULL REFERENCES rings(id),
  cx              INT NOT NULL,
  cy              INT NOT NULL,
  bits            BYTEA NOT NULL CHECK (octet_length(bits) = 128),
  revealed_count  INT NOT NULL DEFAULT 0,
  updated_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
  PRIMARY KEY (ring_id, cx, cy)
);

CREATE TABLE chunk_materialised (
  ring_id          BIGINT NOT NULL REFERENCES rings(id),
  cx               INT NOT NULL,
  cy               INT NOT NULL,
  cache            JSONB,
  materialised_at  TIMESTAMPTZ NOT NULL DEFAULT now(),
  PRIMARY KEY (ring_id, cx, cy)
);

CREATE TABLE cell_reveal_credit (
  ring_id    BIGINT NOT NULL REFERENCES rings(id),
  cx         INT NOT NULL,
  cy         INT NOT NULL,
  player_id  BIGINT NOT NULL REFERENCES players(id),
  count      INT NOT NULL DEFAULT 0,
  PRIMARY KEY (ring_id, cx, cy, player_id)
);

-- Supply ----------------------------------------------------------------------------------------
CREATE TABLE camps (
  id          BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  ring_id     BIGINT NOT NULL REFERENCES rings(id),
  cell_x      INT NOT NULL,
  cell_y      INT NOT NULL,
  name        TEXT,
  kind        TEXT NOT NULL CHECK (kind IN ('camp', 'depot', 'hub')),
  status      TEXT NOT NULL CHECK (status IN ('construction', 'active', 'dry')),
  stock       DOUBLE PRECISION NOT NULL DEFAULT 0,
  built_by    BIGINT REFERENCES players(id),
  created_at  TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE camp_ledger (
  id         BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  camp_id    BIGINT NOT NULL REFERENCES camps(id),
  player_id  BIGINT REFERENCES players(id),
  delta      DOUBLE PRECISION NOT NULL,
  reason     TEXT NOT NULL CHECK (reason IN (
               'deposit', 'withdraw', 'delivery_withdraw', 'delivery_deposit',
               'tank_return', 'tank_refill', 'upkeep', 'build', 'lighthouse')),
  at         TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX camp_ledger_withdraw_window ON camp_ledger (camp_id, player_id, at);

CREATE TABLE player_state (
  player_id    BIGINT PRIMARY KEY REFERENCES players(id),
  ring_id      BIGINT NOT NULL REFERENCES rings(id),
  x            REAL NOT NULL,
  y            REAL NOT NULL,
  yaw          REAL NOT NULL DEFAULT 0,
  lantern_oil  DOUBLE PRECISION NOT NULL DEFAULT 0,
  pack_oil     DOUBLE PRECISION NOT NULL DEFAULT 0,
  lantern_on   BOOLEAN NOT NULL DEFAULT false,
  cart_id      BIGINT,
  updated_at   TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE lanterns (
  id         BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  ring_id    BIGINT NOT NULL REFERENCES rings(id),
  cell_x     INT NOT NULL,
  cell_y     INT NOT NULL,
  camp_id    BIGINT REFERENCES camps(id),
  permanent  BOOLEAN NOT NULL DEFAULT false,
  placed_by  BIGINT REFERENCES players(id),
  placed_at  TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE carts (
  id          BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  ring_id     BIGINT NOT NULL REFERENCES rings(id),
  x           REAL NOT NULL,
  y           REAL NOT NULL,
  oil         DOUBLE PRECISION NOT NULL DEFAULT 0,
  owner_id    BIGINT REFERENCES players(id),
  pushed_by   BIGINT REFERENCES players(id),
  updated_at  TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE cache_claims (
  ring_id     BIGINT NOT NULL REFERENCES rings(id),
  cx          INT NOT NULL,
  cy          INT NOT NULL,
  claimed_by  BIGINT REFERENCES players(id),
  claimed_at  TIMESTAMPTZ NOT NULL DEFAULT now(),
  remaining   JSONB NOT NULL DEFAULT '{}'::jsonb,
  PRIMARY KEY (ring_id, cx, cy)
);

CREATE TABLE supply_requests (
  id            BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  camp_id       BIGINT NOT NULL REFERENCES camps(id),
  amount        DOUBLE PRECISION NOT NULL,
  created_at    TIMESTAMPTZ NOT NULL DEFAULT now(),
  fulfilled_at  TIMESTAMPTZ
);

CREATE TABLE deliveries (
  id            BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  request_id    BIGINT NOT NULL REFERENCES supply_requests(id),
  player_id     BIGINT NOT NULL REFERENCES players(id),
  from_camp_id  BIGINT NOT NULL REFERENCES camps(id),
  to_camp_id    BIGINT NOT NULL REFERENCES camps(id),
  amount        DOUBLE PRECISION NOT NULL,
  delivered     DOUBLE PRECISION NOT NULL DEFAULT 0,
  created_at    TIMESTAMPTZ NOT NULL DEFAULT now(),
  due_at        TIMESTAMPTZ NOT NULL,
  status        TEXT NOT NULL CHECK (status IN ('active', 'delivered', 'shortfall'))
);

-- Collaboration ---------------------------------------------------------------------------------
CREATE TABLE markers (
  id          BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  ring_id     BIGINT NOT NULL REFERENCES rings(id),
  cell_x      INT NOT NULL,
  cell_y      INT NOT NULL,
  kind        TEXT NOT NULL CHECK (kind IN (
                'dead_end', 'route', 'warning', 'cache_empty', 'gate_rumour', 'question', 'camp_site')),
  author_id   BIGINT REFERENCES players(id),
  created_at  TIMESTAMPTZ NOT NULL DEFAULT now(),
  score       REAL NOT NULL DEFAULT 0,
  status      TEXT NOT NULL DEFAULT 'active'
);

CREATE TABLE marker_votes (
  marker_id  BIGINT NOT NULL REFERENCES markers(id),
  player_id  BIGINT NOT NULL REFERENCES players(id),
  vote       SMALLINT NOT NULL CHECK (vote IN (-1, 1)),
  PRIMARY KEY (marker_id, player_id)
);

CREATE TABLE chalk (
  id          BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  ring_id     BIGINT NOT NULL REFERENCES rings(id),
  cell_x      INT NOT NULL,
  cell_y      INT NOT NULL,
  face        CHAR(1) NOT NULL CHECK (face IN ('N', 'E', 'S', 'W')),
  glyph       TEXT NOT NULL,
  author_id   BIGINT REFERENCES players(id),
  created_at  TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE notes (
  id          BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  ring_id     BIGINT NOT NULL REFERENCES rings(id),
  cell_x      INT NOT NULL,
  cell_y      INT NOT NULL,
  text        TEXT NOT NULL CHECK (char_length(text) <= 80),
  author_id   BIGINT REFERENCES players(id),
  created_at  TIMESTAMPTZ NOT NULL DEFAULT now(),
  score       REAL NOT NULL DEFAULT 0,
  status      TEXT NOT NULL DEFAULT 'active'
);

CREATE TABLE note_votes (
  note_id    BIGINT NOT NULL REFERENCES notes(id),
  player_id  BIGINT NOT NULL REFERENCES players(id),
  vote       SMALLINT NOT NULL CHECK (vote IN (-1, 1)),
  PRIMARY KEY (note_id, player_id)
);

CREATE TABLE signposts (
  id          BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  ring_id     BIGINT NOT NULL REFERENCES rings(id),
  cell_x      INT NOT NULL,
  cell_y      INT NOT NULL,
  text        TEXT NOT NULL CHECK (char_length(text) <= 60),
  author_id   BIGINT REFERENCES players(id),
  created_at  TIMESTAMPTZ NOT NULL DEFAULT now(),
  score       REAL NOT NULL DEFAULT 0,
  status      TEXT NOT NULL DEFAULT 'active'
);

CREATE TABLE bells (
  id          BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  ring_id     BIGINT NOT NULL REFERENCES rings(id),
  cell_x      INT NOT NULL,
  cell_y      INT NOT NULL,
  placed_by   BIGINT REFERENCES players(id),
  created_at  TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- Append-only opening overlay (spec §5.10). Edges in owned form: cell (x, y) owns E and S.
CREATE TABLE opened_walls (
  ring_id    BIGINT NOT NULL REFERENCES rings(id),
  cell_x     INT NOT NULL,
  cell_y     INT NOT NULL,
  edge       CHAR(1) NOT NULL CHECK (edge IN ('E', 'S')),
  kind       TEXT NOT NULL CHECK (kind IN ('lever', 'coarse_lever', 'plate', 'gate', 'arrival')),
  opened_by  BIGINT REFERENCES players(id),
  opened_at  TIMESTAMPTZ NOT NULL DEFAULT now(),
  PRIMARY KEY (ring_id, cell_x, cell_y, edge)
);

CREATE TABLE gates (
  id             BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  ring_id        BIGINT NOT NULL REFERENCES rings(id),
  slot_index     INT NOT NULL,
  t_fix          BIGINT NOT NULL CHECK (t_fix >= 0 AND t_fix <= 4294967295),
  t              REAL NOT NULL,
  cell_x         INT NOT NULL,
  cell_y         INT NOT NULL,
  active         BOOLEAN NOT NULL,
  extra          BOOLEAN NOT NULL DEFAULT false,
  activated_at   TIMESTAMPTZ,
  discovered_by  BIGINT REFERENCES players(id),
  discovered_at  TIMESTAMPTZ,
  UNIQUE (ring_id, slot_index)
);

CREATE TABLE district_names (
  ring_id   BIGINT NOT NULL REFERENCES rings(id),
  cx        INT NOT NULL,
  cy        INT NOT NULL,
  name      TEXT NOT NULL CHECK (char_length(name) <= 30),
  named_by  BIGINT REFERENCES players(id),
  named_at  TIMESTAMPTZ NOT NULL DEFAULT now(),
  PRIMARY KEY (ring_id, cx, cy)
);

CREATE TABLE lead_claims (
  id          BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  ring_id     BIGINT NOT NULL REFERENCES rings(id),
  lead_key    TEXT NOT NULL,
  player_id   BIGINT NOT NULL REFERENCES players(id),
  claimed_at  TIMESTAMPTZ NOT NULL DEFAULT now(),
  expires_at  TIMESTAMPTZ NOT NULL,
  status      TEXT NOT NULL CHECK (status IN ('active', 'released', 'completed', 'expired'))
);

CREATE TABLE threads (
  player_id   BIGINT PRIMARY KEY REFERENCES players(id),
  points      BYTEA NOT NULL,
  updated_at  TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE footprints_hourly (
  ring_id      BIGINT NOT NULL REFERENCES rings(id),
  cx           INT NOT NULL,
  cy           INT NOT NULL,
  hour_bucket  TIMESTAMPTZ NOT NULL,
  counts       BYTEA NOT NULL,
  PRIMARY KEY (ring_id, cx, cy, hour_bucket)
);

CREATE TABLE pings (
  id          BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  ring_id     BIGINT NOT NULL REFERENCES rings(id),
  cell_x      INT NOT NULL,
  cell_y      INT NOT NULL,
  kind        TEXT NOT NULL CHECK (kind IN ('need_partner', 'help', 'follow_me', 'oil_here', 'lost')),
  player_id   BIGINT NOT NULL REFERENCES players(id),
  created_at  TIMESTAMPTZ NOT NULL DEFAULT now(),
  expires_at  TIMESTAMPTZ NOT NULL
);

-- Finale ----------------------------------------------------------------------------------------
CREATE TABLE lighthouse (
  world_id                 BIGINT PRIMARY KEY REFERENCES worlds(id),
  oil_required             DOUBLE PRECISION,
  oil_stored               DOUBLE PRECISION NOT NULL DEFAULT 0,
  kindling_started_at      TIMESTAMPTZ,
  ignition_scheduled_at    TIMESTAMPTZ,
  ignited_at               TIMESTAMPTZ,
  first_arrival_player_id  BIGINT REFERENCES players(id),
  first_arrival_at         TIMESTAMPTZ
);

CREATE TABLE lighthouse_contributions (
  player_id  BIGINT PRIMARY KEY REFERENCES players(id),
  oil        DOUBLE PRECISION NOT NULL DEFAULT 0,
  last_at    TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- Meta ------------------------------------------------------------------------------------------
CREATE TABLE chronicle_events (
  id       BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  at       TIMESTAMPTZ NOT NULL DEFAULT now(),
  kind     TEXT NOT NULL,
  payload  JSONB NOT NULL DEFAULT '{}'::jsonb
);

CREATE TABLE exploration_daily (
  day             DATE NOT NULL,
  ring_id         BIGINT NOT NULL REFERENCES rings(id),
  new_cells       BIGINT NOT NULL DEFAULT 0,
  active_players  INT NOT NULL DEFAULT 0,
  PRIMARY KEY (day, ring_id)
);

CREATE TABLE pacing_log (
  id        BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  at        TIMESTAMPTZ NOT NULL DEFAULT now(),
  decision  JSONB NOT NULL
);

CREATE TABLE reports (
  id           BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  reporter_id  BIGINT NOT NULL REFERENCES players(id),
  target_kind  TEXT NOT NULL,
  target_id    BIGINT NOT NULL,
  reason       TEXT NOT NULL,
  at           TIMESTAMPTZ NOT NULL DEFAULT now(),
  status       TEXT NOT NULL DEFAULT 'open'
);

CREATE TABLE behaviour_flags (
  id         BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  player_id  BIGINT NOT NULL REFERENCES players(id),
  kind       TEXT NOT NULL,
  score      REAL NOT NULL,
  at         TIMESTAMPTZ NOT NULL DEFAULT now()
);
