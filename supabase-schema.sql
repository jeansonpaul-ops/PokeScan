-- PokéScan v4 — schéma Supabase (déjà appliqué sur le projet « Pokescan » le 13/11/2026)
-- Conservé pour référence : ce fichier peut être relancé sans risque.

create table if not exists public.cards (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null default auth.uid() references auth.users(id) on delete cascade,
  name text not null, types text[] default '{}', set_code text, number text,
  finish text default 'Standard', lang text default 'fr', set_name text, image_url text,
  price_eur numeric, price_usd numeric, price_updated_at timestamptz, tcg_id text, rarity text,
  quantity int not null default 1 check (quantity > 0), condition text default 'Near Mint', notes text,
  created_at timestamptz default now(), updated_at timestamptz default now()
);
alter table public.cards add column if not exists lang text default 'fr';
alter table public.cards add column if not exists price_updated_at timestamptz;
alter table public.cards drop column if exists thumbnail;
alter table public.cards add column if not exists price_fr numeric;       -- prix des offres en français, saisi à la main
alter table public.cards add column if not exists price_fr_at timestamptz;
alter table public.cards add column if not exists price_fr_src text;
alter table public.cards add column if not exists price_fr_low numeric;
alter table public.cards add column if not exists valo_id integer;
create index if not exists idx_cards_user on public.cards(user_id);
create index if not exists idx_cards_set on public.cards(user_id, set_code, number);

create or replace function public.update_updated_at()
returns trigger language plpgsql set search_path = '' as $$
begin new.updated_at = now(); return new; end; $$;
drop trigger if exists cards_updated_at on public.cards;
create trigger cards_updated_at before update on public.cards for each row execute function public.update_updated_at();

-- Chacun ne voit et ne modifie que ses cartes ; les visiteurs non connectés n'ont aucun accès
alter table public.cards enable row level security;
drop policy if exists "Lecture propres cartes" on public.cards;
drop policy if exists "Insertion propres cartes" on public.cards;
drop policy if exists "Modification propres cartes" on public.cards;
drop policy if exists "Suppression propres cartes" on public.cards;
create policy "Lecture propres cartes" on public.cards for select to authenticated using ((select auth.uid()) = user_id);
create policy "Insertion propres cartes" on public.cards for insert to authenticated with check ((select auth.uid()) = user_id);
create policy "Modification propres cartes" on public.cards for update to authenticated using ((select auth.uid()) = user_id) with check ((select auth.uid()) = user_id);
create policy "Suppression propres cartes" on public.cards for delete to authenticated using ((select auth.uid()) = user_id);
revoke all on public.cards from anon;
drop view if exists public.stats;
