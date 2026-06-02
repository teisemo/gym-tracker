-- ══════════════════════════════════════════════════════════
--  GymBroTracker — Schema completo (struttura normalizzata)
--  Per NUOVE installazioni. Esegui tutto in un'unica query.
-- ══════════════════════════════════════════════════════════

-- ── PROFILES ──────────────────────────────────────────────
create table if not exists public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  email text, display_name text, updated_at timestamptz default now()
);
alter table public.profiles enable row level security;
create policy "profiles_select" on public.profiles for select to authenticated using (true);
create policy "profiles_insert" on public.profiles for insert to authenticated with check (id = auth.uid());
create policy "profiles_update" on public.profiles for update to authenticated using (id = auth.uid()) with check (id = auth.uid());
grant all on public.profiles to authenticated;
grant usage on schema public to authenticated, anon;
create or replace function public.handle_new_user()
returns trigger language plpgsql security definer as $$
begin
  insert into public.profiles (id, email, display_name)
  values (new.id, new.email, coalesce(new.raw_user_meta_data->>'display_name', split_part(new.email,'@',1)))
  on conflict (id) do nothing;
  return new;
end; $$;
drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created after insert on auth.users
  for each row execute function public.handle_new_user();

-- ── ATHLETES ──────────────────────────────────────────────
create table if not exists public.athletes (
  id serial primary key, nome text not null, cognome text not null default '',
  position smallint not null default 0, active boolean not null default true,
  created_at timestamptz default now()
);
alter table public.athletes enable row level security;
create policy "athletes_select" on public.athletes for select to authenticated using (true);
create policy "athletes_insert" on public.athletes for insert to authenticated with check (true);
create policy "athletes_update" on public.athletes for update to authenticated using (true) with check (true);
create policy "athletes_delete" on public.athletes for delete to authenticated using (true);
grant select, insert, update, delete on public.athletes to authenticated;
grant usage, select on sequence public.athletes_id_seq to authenticated;

-- ── WORKOUTS (schede) ─────────────────────────────────────
create table if not exists public.workouts (
  id serial primary key, nome text not null, short text not null default '',
  position smallint not null default 0, active boolean not null default true,
  created_at timestamptz default now()
);
alter table public.workouts enable row level security;
create policy "workouts_select" on public.workouts for select to authenticated using (true);
create policy "workouts_insert" on public.workouts for insert to authenticated with check (true);
create policy "workouts_update" on public.workouts for update to authenticated using (true) with check (true);
create policy "workouts_delete" on public.workouts for delete to authenticated using (true);
grant select, insert, update, delete on public.workouts to authenticated;
grant usage, select on sequence public.workouts_id_seq to authenticated;

insert into public.workouts (nome, short, position) values
  ('Allenamento 1','A1',0),('Allenamento 2','A2',1),('Allenamento 3','A3',2);

-- ── EXERCISES (catalogo globale) ──────────────────────────
create table if not exists public.exercises (
  id serial primary key,
  nome text not null unique,
  gruppo_muscolare text,
  created_at timestamptz default now()
);
alter table public.exercises enable row level security;
create policy "exercises_select" on public.exercises for select to authenticated using (true);
create policy "exercises_insert" on public.exercises for insert to authenticated with check (true);
create policy "exercises_update" on public.exercises for update to authenticated using (true) with check (true);
create policy "exercises_delete" on public.exercises for delete to authenticated using (true);
grant select, insert, update, delete on public.exercises to authenticated;
grant usage, select on sequence public.exercises_id_seq to authenticated;

insert into public.exercises (nome, gruppo_muscolare) values
  ('LEG EXTENSIONS','QUADRICIPITI'),('LEG CURL','FEMORALI'),('PANCA PIANA','PETTORALI'),
  ('LAT MACHINE','DORSALI'),('HAMMER CURL','BICIPITI'),
  ('STACCO DA TERRA','FEMORALI'),('TRAZIONI ALLA SBARRA','DORSALI'),('PARALLELE','PETTORALI'),
  ('SPINTE PER LE SPALLE','DELTOIDI'),('CURL AL CAVO','BICIPITI'),
  ('SQUAT','QUADRICIPITI'),('REMATORE','UPPER BACK'),('CROCI SU PANCA INCLINATA','PETTORALI'),
  ('ALZATE LATERALI','DELTOIDI'),('SPINTE IN BASSO BARRA','TRICIPITI')
on conflict (nome) do nothing;

-- ── WORKOUT_EXERCISES (collegamento scheda ↔ esercizio) ───
create table if not exists public.workout_exercises (
  id serial primary key,
  workout_id integer not null references public.workouts(id) on delete cascade,
  exercise_id integer not null references public.exercises(id) on delete cascade,
  position smallint not null default 0,
  tempo text not null default '3111',
  range_rip text not null default '6-10',
  created_at timestamptz default now(),
  unique (workout_id, exercise_id)
);
alter table public.workout_exercises enable row level security;
create policy "we_select" on public.workout_exercises for select to authenticated using (true);
create policy "we_insert" on public.workout_exercises for insert to authenticated with check (true);
create policy "we_update" on public.workout_exercises for update to authenticated using (true) with check (true);
create policy "we_delete" on public.workout_exercises for delete to authenticated using (true);
grant select, insert, update, delete on public.workout_exercises to authenticated;
grant usage, select on sequence public.workout_exercises_id_seq to authenticated;
create index idx_we_workout on public.workout_exercises (workout_id, position);

-- Collega gli esercizi default alle 3 schede
insert into public.workout_exercises (workout_id, exercise_id, position, tempo, range_rip)
select w.id, e.id, d.position, d.tempo, d.range_rip
from (values
  ('A1','LEG EXTENSIONS',0,'3111','6-10'),
  ('A1','LEG CURL',1,'3111','6-10'),
  ('A1','PANCA PIANA',2,'3111','6-10'),
  ('A1','LAT MACHINE',3,'2111','6-10'),
  ('A1','HAMMER CURL',4,'3111','6-10'),
  ('A2','STACCO DA TERRA',0,'3111','6-10'),
  ('A2','TRAZIONI ALLA SBARRA',1,'3111','6-10'),
  ('A2','PARALLELE',2,'3111','6-10'),
  ('A2','SPINTE PER LE SPALLE',3,'3111','6-10'),
  ('A2','CURL AL CAVO',4,'3111','6-10'),
  ('A3','SQUAT',0,'2111','6-10'),
  ('A3','REMATORE',1,'3111','6-10'),
  ('A3','CROCI SU PANCA INCLINATA',2,'3111','6-10'),
  ('A3','ALZATE LATERALI',3,'2111','6-10'),
  ('A3','SPINTE IN BASSO BARRA',4,'3111','6-10')
) as d(wshort, exnome, position, tempo, range_rip)
join public.workouts w on w.short = d.wshort
join public.exercises e on e.nome = d.exnome;

-- ── WORKOUT_SESSIONS ──────────────────────────────────────
create table if not exists public.workout_sessions (
  id bigserial primary key,
  user_id uuid not null references auth.users(id) on delete cascade,
  athlete_id integer references public.athletes(id) on delete set null,
  workout_id integer references public.workouts(id) on delete set null,
  session_date date,
  series_data jsonb default '{}'::jsonb,   -- indicizzato per exercise_id
  created_at timestamptz default now(),
  updated_at timestamptz default now(),
  unique (user_id, athlete_id, session_date, workout_id)
);
alter table public.workout_sessions enable row level security;
create policy "ws_select" on public.workout_sessions for select to authenticated using (true);
create policy "ws_insert" on public.workout_sessions for insert to authenticated with check (user_id = auth.uid());
create policy "ws_update" on public.workout_sessions for update to authenticated using (user_id = auth.uid()) with check (user_id = auth.uid());
create policy "ws_delete" on public.workout_sessions for delete to authenticated using (user_id = auth.uid());
grant select, insert, update, delete on public.workout_sessions to authenticated;
grant usage, select on sequence public.workout_sessions_id_seq to authenticated;
create index idx_ws_user on public.workout_sessions (user_id);
create index idx_ws_athlete on public.workout_sessions (athlete_id);
create index idx_ws_workout on public.workout_sessions (workout_id);
create index idx_ws_date on public.workout_sessions (session_date desc);

-- ── VERIFICA ──────────────────────────────────────────────
select 'esercizi' as tbl, count(*) from public.exercises
union all select 'collegamenti', count(*) from public.workout_exercises
union all select 'schede', count(*) from public.workouts;
