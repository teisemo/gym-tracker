-- ══════════════════════════════════════════════════════════
--  Aggiungi colonna gruppo_muscolare alla tabella exercises
--  (Solo se non l'hai già aggiunta manualmente)
--  Idempotente: sicuro da rieseguire
-- ══════════════════════════════════════════════════════════

alter table public.exercises
  add column if not exists gruppo_muscolare text;

-- Verifica
select column_name, data_type
from information_schema.columns
where table_schema='public' and table_name='exercises'
order by ordinal_position;
