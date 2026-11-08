-- Simula o mínimo do Supabase: papéis, auth.uid(), publicação realtime e as
-- tabelas que já existem no projeto real (station_user_access e a tabela antiga).
do $$ begin
  if not exists (select 1 from pg_roles where rolname='anon') then create role anon nologin; end if;
  if not exists (select 1 from pg_roles where rolname='authenticated') then create role authenticated nologin; end if;
end $$;
grant usage on schema public to anon, authenticated;
alter default privileges in schema public grant all on tables to anon, authenticated;
alter default privileges in schema public grant all on functions to anon, authenticated;
create schema auth;
grant usage on schema auth to anon, authenticated;
create function auth.uid() returns uuid language sql stable as $$
  select nullif(current_setting('request.jwt.claims', true)::json->>'sub', '')::uuid $$;
create publication supabase_realtime;

create table public.station_user_access (user_id uuid primary key, role text not null, editor_name text);
alter table public.station_user_access enable row level security;
create policy read_all on public.station_user_access for select to authenticated using (true);

create table public.editor_panel_shared_data (id int primary key, payload jsonb, updated_at timestamptz, updated_by uuid);
alter table public.editor_panel_shared_data enable row level security;
create policy rw on public.editor_panel_shared_data for all to authenticated using (true) with check (true);

insert into public.station_user_access values
 ('aaaaaaaa-0000-0000-0000-000000000001','admin','Admin'),
 ('cccccccc-0000-0000-0000-000000000001','chief','Chefe Carla'),
 ('eeeeeeee-0000-0000-0000-000000000001','editor','Ana'),
 ('eeeeeeee-0000-0000-0000-000000000002','editor','Bruno'),
 ('eeeeeeee-0000-0000-0000-000000000003','editor','Duda'),
 ('eeeeeeee-0000-0000-0000-000000000004','editor','duda ');  -- nome duplicado: não deve vincular por nome
