-- ============================================================
-- ALRG — Complete database schema (Supabase / Postgres)
-- Paste this whole file into Supabase SQL Editor and Run.
-- Safe to re-run: drops and recreates ALRG tables.
-- ============================================================

drop table if exists verifications cascade;
drop table if exists menu_items cascade;
drop table if exists restaurants cascade;
drop table if exists chains cascade;
drop table if exists metros cascade;
drop table if exists ops_log cascade;

-- ---------- reference: metro processing queue ----------
create table metros (
  id            bigint generated always as identity primary key,
  name          text not null,
  state         text not null,
  rank          int,                      -- population rank; batch order
  status        text not null default 'queued',  -- queued | in_progress | complete
  completed_at  timestamptz
);

-- ---------- chains (one menu analysis -> many locations) ----------
create table chains (
  id             bigint generated always as identity primary key,
  name           text not null unique,
  official_matrix boolean default false,  -- true = published allergen matrix (highest confidence)
  analyzed_at    timestamptz,
  source_document text  -- real document/page the allergen data came from (one per chain,
                         -- not per item — see pipeline/README.md for why this lives here
                         -- and not in menu_items.note)
);

-- ---------- restaurants ----------
create table restaurants (
  id            bigint generated always as identity primary key,
  place_id      text unique,              -- external join key only; no cached vendor content
  name          text not null,
  cuisine       text,
  address       text,
  city          text,
  state         text,
  zip           text,
  lat           double precision,
  lng           double precision,
  chain_id      bigint references chains(id),
  verified      boolean default false,    -- restaurant-confirmed data
  data_source   text default 'ai_pipeline', -- ai_pipeline | chain_matrix | restaurant_verified
  source_document text,  -- independents only (chains use chains.source_document instead) —
                          -- the real page/document the menu+allergen data came from. Be
                          -- honest here: note it explicitly if the source is weak (press
                          -- coverage instead of the restaurant's own menu, a third-party
                          -- aggregator) rather than presenting it as equal-confidence.
  -- phone/website (2026-09-23) exist for the paid-places-API upgrade
  -- (pipeline/PAID_UPGRADE_POINTS.md #3/#5) — null until that's active.
  -- Populate them from a restaurant's own site, independently
  -- re-verified after Places surfaces it as a discovery lead, never
  -- copied straight from Places' own fields — see
  -- pipeline/COVERAGE_PLAN.md for why. Never fabricate either; null is
  -- the honest state today.
  --
  -- No rating/rating_count column: a Places-sourced star rating must be
  -- requested live and displayed with attribution on every view per
  -- Google's terms, not stored — that's incompatible with how every
  -- other field in this table works (populate once, serve from
  -- Supabase), so it was dropped from the plan 2026-09-23 rather than
  -- built in a way that couldn't actually be shipped. Distance remains
  -- the real, honest sort signal (see app/index.html renderList).
  phone         text,
  website       text,
  last_reviewed timestamptz default now(),
  created_at    timestamptz default now()
);
create index idx_rest_geo  on restaurants (state, city);
create index idx_rest_zip  on restaurants (zip);

-- ---------- menu items with allergen flags ----------
-- flags JSONB: {"peanut":"contains","dairy":"may","wheat":"shared"} ; absent = clear
-- statuses: contains | may | shared  (clear is implicit)
create table menu_items (
  id            bigint generated always as identity primary key,
  restaurant_id bigint not null references restaurants(id) on delete cascade,
  name          text not null,
  note          text,
  flags         jsonb not null default '{}'::jsonb,
  audited       boolean default false     -- passed qa-allergen-auditor
);
create index idx_items_rest on menu_items (restaurant_id);
create index idx_items_flags on menu_items using gin (flags);

-- ---------- community verifications ----------
create table verifications (
  id            bigint generated always as identity primary key,
  restaurant_id bigint not null references restaurants(id) on delete cascade,
  allergen      text not null,
  outcome       text not null,            -- safe_experience | reaction_reported | info_correction
  comment       text,
  status        text not null default 'pending',  -- pending | approved | rejected
  created_at    timestamptz default now()
);

-- ---------- ops log (batch runs, imports, audits) ----------
create table ops_log (
  id         bigint generated always as identity primary key,
  event      text not null,
  detail     jsonb,
  created_at timestamptz default now()
);

-- ============================================================
-- Row Level Security: public can READ published data;
-- all writes require the service role (pipeline/admin only).
-- ============================================================
alter table restaurants   enable row level security;
alter table menu_items    enable row level security;
alter table chains        enable row level security;
alter table metros        enable row level security;
alter table verifications enable row level security;
alter table ops_log       enable row level security;

create policy "public read restaurants" on restaurants for select using (true);
create policy "public read items"       on menu_items  for select using (true);
create policy "public read chains"      on chains      for select using (true);
-- anyone may SUBMIT a verification; only service role reads/updates them
create policy "public submit verification" on verifications for insert with check (true);

-- ============================================================
-- NOTE: this file used to seed 4 hardcoded "Demo St" restaurants here
-- so the app had something to show immediately after setup. Removed
-- 2026-09-23 — they were fabricated data (fake addresses, made-up
-- menus/allergen flags) that ended up marked verified=true in
-- production, presenting fictional content with the same authority as
-- real, audited restaurants. Never re-add placeholder restaurant data
-- to this schema, seed or otherwise — an empty map until the pipeline
-- publishes real data is the honest state, not a demo restaurant.
-- ============================================================

-- Seed covers all 50 states (2026-09-23, nationwide coverage plan —
-- see pipeline/COVERAGE_PLAN.md) so every state has at least one
-- discovery entry point for the independent-restaurant pipeline. Rank
-- is a rough population-order hint for batch priority, not an
-- authoritative figure — fine to be approximate.
insert into metros (name,state,rank,status,completed_at) values
('Denver','CO',19,'complete',now()),
('New York','NY',1,'queued',null),
('Los Angeles','CA',2,'queued',null),
('Chicago','IL',3,'queued',null),
('Dallas','TX',4,'queued',null),
('Houston','TX',5,'queued',null),
('Washington','DC',6,'queued',null),
('Philadelphia','PA',7,'queued',null),
('Atlanta','GA',8,'queued',null),
('Miami','FL',9,'queued',null),
('Phoenix','AZ',10,'queued',null),
('Boston','MA',11,'queued',null),
('San Francisco','CA',12,'queued',null),
('Seattle','WA',14,'queued',null),
('Minneapolis','MN',16,'queued',null),
('San Diego','CA',17,'queued',null),
('Tampa','FL',18,'queued',null),
('St. Louis','MO',20,'queued',null),
('Columbus','OH',21,'queued',null),
('Charlotte','NC',22,'queued',null),
('Indianapolis','IN',23,'queued',null),
('Nashville','TN',24,'queued',null),
('Detroit','MI',25,'queued',null),
('Oklahoma City','OK',26,'queued',null),
('Las Vegas','NV',27,'queued',null),
('Louisville','KY',28,'queued',null),
('Baltimore','MD',29,'queued',null),
('Milwaukee','WI',30,'queued',null),
('Albuquerque','NM',31,'queued',null),
('New Orleans','LA',32,'queued',null),
('Honolulu','HI',33,'queued',null),
('Wichita','KS',34,'queued',null),
('Newark','NJ',35,'queued',null),
('Virginia Beach','VA',36,'queued',null),
('Providence','RI',37,'queued',null),
('Portland','OR',38,'queued',null),
('Boise','ID',39,'queued',null),
('Des Moines','IA',40,'queued',null),
('Omaha','NE',41,'queued',null),
('Anchorage','AK',42,'queued',null),
('Bridgeport','CT',43,'queued',null),
('Birmingham','AL',44,'queued',null),
('Little Rock','AR',45,'queued',null),
('Wilmington','DE',46,'queued',null),
('Manchester','NH',47,'queued',null),
('Jackson','MS',48,'queued',null),
('Portland','ME',49,'queued',null),
('Sioux Falls','SD',50,'queued',null),
('Charleston','SC',51,'queued',null),
('Salt Lake City','UT',52,'queued',null),
('Fargo','ND',53,'queued',null),
('Billings','MT',54,'queued',null),
('Burlington','VT',55,'queued',null),
('Cheyenne','WY',56,'queued',null),
('Charleston','WV',57,'queued',null);

-- Chains backlog: names only, from public knowledge. NO allergen data is
-- seeded here — chain-menu-importer sources and audits each one for real
-- before analyzed_at is set. Ranked loosely by known footprint size; order
-- just determines what gets imported first, not confidence.
insert into chains (name) values
('McDonald''s'),('Subway'),('Starbucks'),('Taco Bell'),('Wendy''s'),
('Burger King'),('Domino''s Pizza'),('Dunkin'''),('Chick-fil-A'),
('Pizza Hut'),('Chipotle Mexican Grill'),('Panera Bread'),
('Sonic Drive-In'),('Dairy Queen'),('Popeyes'),('Arby''s'),
('Panda Express'),('Jimmy John''s'),('Jersey Mike''s Subs'),
('Five Guys'),('Chili''s'),('Applebee''s'),('Olive Garden'),
('Buffalo Wild Wings'),('IHOP'),('Denny''s'),('Cracker Barrel'),
('Outback Steakhouse'),('Texas Roadhouse'),('Red Lobster');

insert into ops_log (event,detail) values ('schema_installed','{"version":"1.0","seed":"denver_sample_plus_chains_backlog"}');
