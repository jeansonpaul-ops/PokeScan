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

-- ════════════════════════════════════════════════════════════
-- Famille (v4.3) : demandes d'accès validées par l'administrateur,
-- vitrines lisibles entre membres, chacun ne modifie que la sienne.
-- (migration appliquée : pokescan_family_requests)
-- ════════════════════════════════════════════════════════════
create schema if not exists private;
revoke all on schema private from public, anon;
grant usage on schema private to authenticated;

create table if not exists public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  email text not null,
  display_name text not null default '' check (length(display_name) <= 40),
  status text not null default 'pending' check (status in ('pending','member','refused')),
  is_admin boolean not null default false,
  created_at timestamptz not null default now(),
  decided_at timestamptz
);
alter table public.profiles enable row level security;
revoke all on public.profiles from anon, authenticated;
grant select on public.profiles to authenticated;

create or replace function private.is_member() returns boolean language sql stable security definer set search_path = '' as $$
  select exists (select 1 from public.profiles where id = (select auth.uid()) and status = 'member');
$$;
create or replace function private.is_admin() returns boolean language sql stable security definer set search_path = '' as $$
  select exists (select 1 from public.profiles where id = (select auth.uid()) and status = 'member' and is_admin);
$$;
revoke all on function private.is_member(), private.is_admin() from public, anon;
grant execute on function private.is_member(), private.is_admin() to authenticated;

create policy "Profils : soi, membres, admin" on public.profiles for select to authenticated using (
  id = (select auth.uid()) or ((select private.is_member()) and status = 'member') or (select private.is_admin()));

create or replace function private.new_user() returns trigger language plpgsql security definer set search_path = '' as $$
begin
  insert into public.profiles (id, email, display_name)
  values (new.id, lower(new.email), left(coalesce(nullif(trim(new.raw_user_meta_data->>'name'), ''), split_part(new.email, '@', 1)), 40))
  on conflict (id) do nothing;
  return new;
end $$;
create trigger pokescan_new_user after insert on auth.users for each row execute function private.new_user();
create or replace function private.confirm_user() returns trigger language plpgsql security definer set search_path = '' as $$
begin new.email_confirmed_at := coalesce(new.email_confirmed_at, now()); return new; end $$;
create trigger pokescan_confirm_user before insert on auth.users for each row execute function private.confirm_user();

create or replace function public.family_decide(p_id uuid, p_accept boolean) returns void
language plpgsql security definer set search_path = '' as $$
begin
  if not (select private.is_admin()) then raise exception 'Réservé à l''administrateur'; end if;
  if p_id = (select auth.uid()) then raise exception 'Tu ne peux pas changer ton propre accès'; end if;
  update public.profiles set status = case when p_accept then 'member' else 'refused' end, decided_at = now() where id = p_id;
end $$;
revoke all on function public.family_decide(uuid, boolean) from public, anon;
grant execute on function public.family_decide(uuid, boolean) to authenticated;

drop policy if exists "Lecture propres cartes" on public.cards;
drop policy if exists "Insertion propres cartes" on public.cards;
drop policy if exists "Modification propres cartes" on public.cards;
drop policy if exists "Suppression propres cartes" on public.cards;
create policy "Lecture vitrines de la famille" on public.cards for select to authenticated using (
  (select private.is_member()) and (user_id = (select auth.uid()) or exists (select 1 from public.profiles p where p.id = cards.user_id and p.status = 'member')));
create policy "Ajout dans sa vitrine" on public.cards for insert to authenticated
  with check ((select private.is_member()) and user_id = (select auth.uid()));
create policy "Modification de sa vitrine" on public.cards for update to authenticated
  using ((select private.is_member()) and user_id = (select auth.uid())) with check (user_id = (select auth.uid()));
create policy "Suppression dans sa vitrine" on public.cards for delete to authenticated
  using ((select private.is_member()) and user_id = (select auth.uid()));

-- Administrateur (à adapter) :
-- insert into public.profiles (id, email, display_name, status, is_admin, decided_at)
-- select id, lower(email), 'Paul', 'member', true, now() from auth.users where lower(email) = 'ton.email@exemple.com'
-- on conflict (id) do update set status = 'member', is_admin = true;
