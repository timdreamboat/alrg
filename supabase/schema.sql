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
  analyzed_at    timestamptz
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
-- Seed: Denver sample data so the app works immediately
-- ============================================================
insert into restaurants (name,cuisine,address,city,state,zip,lat,lng,verified,data_source) values
('Copper Kettle Kitchen','New American','1 Demo St','Denver','CO','80202',39.7508,-104.9966,true ,'ai_pipeline'),
('Maria''s Taqueria','Mexican','2 Demo St','Denver','CO','80211',39.7614,-105.0166,true ,'ai_pipeline'),
('Golden Lotus','Thai','3 Demo St','Denver','CO','80203',39.7312,-104.9826,false,'ai_pipeline'),
('Verde Bowl Co.','Salads & grain bowls','4 Demo St','Denver','CO','80206',39.7402,-104.9500,true ,'ai_pipeline');

insert into menu_items (restaurant_id,name,note,flags) values
(1,'Grilled salmon bowl','Quinoa, roasted veg','{}'),
(1,'Thai chop salad','Peanut-lime dressing','{"peanut":"contains","soy":"may"}'),
(1,'House fries','Shared fryer','{"peanut":"shared","wheat":"shared"}'),
(1,'Roast chicken plate','Herb jus','{}'),
(2,'Chicken street tacos','Corn tortillas','{}'),
(2,'Carnitas bowl','Rice, beans, pico','{}'),
(2,'Queso fundido','Melted cheese','{"dairy":"contains"}'),
(2,'Churros','Fried, sugar dusted','{"wheat":"contains","egg":"contains","dairy":"may"}'),
(3,'Pad thai','Tamarind, crushed peanut','{"peanut":"contains","egg":"contains","soy":"contains","shellfish":"may"}'),
(3,'Green curry','Coconut milk','{"peanut":"may","shellfish":"may","soy":"may"}'),
(3,'Satay skewers','Peanut sauce','{"peanut":"contains","soy":"contains"}'),
(4,'Harvest grain bowl','Farro base','{"wheat":"may"}'),
(4,'Citrus kale salad','No nuts in-house','{}'),
(4,'Chili-lime chicken bowl','Rice base','{}'),
(4,'Green goddess bowl','Tahini dressing','{"sesame":"contains"}');

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
('St. Louis','MO',20,'queued',null);

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
