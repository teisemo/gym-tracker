-- ══════════════════════════════════════════════════════════
--  GymBroTracker — Migrazione a struttura normalizzata
--  exercises (catalogo) + workout_exercises (collegamento)
--  series_data indicizzato per exercise_id
--
--  ⚠️ FAI UN BACKUP prima di eseguire:
--     Supabase → Database → Backups, oppure esporta workout_sessions
--  Esegui TUTTO in un'unica query
-- ══════════════════════════════════════════════════════════

-- ── 1. NUOVA TABELLA: catalogo esercizi globale ───────────
-- La vecchia tabella exercises diventa il catalogo, ma le servono
-- modifiche. Creiamo una struttura pulita.

-- Rinomina la vecchia tabella per backup
alter table public.exercises rename to exercises_old;

-- Nuovo catalogo esercizi (un esercizio = una riga, id stabile)
create table public.exercises (
  id          serial primary key,
  nome        text not null unique,   -- nome univoco nel catalogo
  created_at  timestamptz default now()
);
alter table public.exercises enable row level security;
create policy "exercises_select" on public.exercises for select to authenticated using (true);
create policy "exercises_insert" on public.exercises for insert to authenticated with check (true);
create policy "exercises_update" on public.exercises for update to authenticated using (true) with check (true);
create policy "exercises_delete" on public.exercises for delete to authenticated using (true);
grant select, insert, update, delete on public.exercises to authenticated;
grant usage, select on sequence public.exercises_id_seq to authenticated;

-- Popola il catalogo con i nomi distinti dalla vecchia tabella
insert into public.exercises (nome)
select distinct nome from public.exercises_old
on conflict (nome) do nothing;

-- ── 2. TABELLA DI COLLEGAMENTO scheda ↔ esercizio ─────────
create table public.workout_exercises (
  id          serial primary key,
  workout_id  integer not null references public.workouts(id) on delete cascade,
  exercise_id integer not null references public.exercises(id) on delete cascade,
  position    smallint not null default 0,
  tempo       text not null default '3111',
  range_rip   text not null default '6-10',
  created_at  timestamptz default now(),
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

-- Popola workout_exercises dalla vecchia tabella exercises_old
insert into public.workout_exercises (workout_id, exercise_id, position, tempo, range_rip)
select
  eo.workout_id,
  e.id as exercise_id,
  eo.position,
  eo.tempo,
  eo.range_rip
from public.exercises_old eo
join public.exercises e on e.nome = eo.nome
where eo.workout_id is not null
on conflict (workout_id, exercise_id) do nothing;

-- ── 3. MIGRA series_data: da indice-posizione a exercise_id ──
-- Le sessioni hanno series_data come {0:{...},1:{...}} dove 0,1 = posizione.
-- Dobbiamo convertirle in {exercise_id:{...}}.
-- Per ogni sessione, mappiamo posizione → exercise_id usando workout_exercises.

do $$
declare
  sess record;
  new_data jsonb;
  pos_key text;
  ex_id integer;
begin
  for sess in
    select ws.id, ws.workout_id, ws.series_data
    from public.workout_sessions ws
    where ws.series_data is not null and ws.series_data != '{}'::jsonb
  loop
    new_data := '{}'::jsonb;
    -- Per ogni chiave (posizione) nel series_data
    for pos_key in select jsonb_object_keys(sess.series_data)
    loop
      -- Trova l'exercise_id corrispondente a (workout_id, position)
      select we.exercise_id into ex_id
      from public.workout_exercises we
      where we.workout_id = sess.workout_id
        and we.position = pos_key::smallint
      limit 1;

      if ex_id is not null then
        new_data := new_data || jsonb_build_object(ex_id::text, sess.series_data -> pos_key);
      end if;
    end loop;

    -- Aggiorna la sessione con i nuovi dati indicizzati per exercise_id
    update public.workout_sessions
      set series_data = new_data
      where id = sess.id;
  end loop;
end $$;

-- ── 4. PULIZIA ─────────────────────────────────────────────
-- Tieni exercises_old come backup. Per eliminarla dopo aver verificato:
-- drop table public.exercises_old;

-- ── 5. VERIFICA ───────────────────────────────────────────
select 'esercizi catalogo' as info, count(*)::text as valore from public.exercises
union all
select 'collegamenti scheda-esercizio', count(*)::text from public.workout_exercises
union all
select 'sessioni totali', count(*)::text from public.workout_sessions
union all
select 'sessioni migrate (con dati)', count(*)::text from public.workout_sessions where series_data != '{}'::jsonb;

-- Mostra un esempio di series_data migrato per controllo
select id, workout_id, series_data
from public.workout_sessions
where series_data != '{}'::jsonb
limit 3;
