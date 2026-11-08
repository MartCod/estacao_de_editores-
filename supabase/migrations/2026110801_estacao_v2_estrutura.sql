-- =============================================================================
-- Estação de Editores 2.0 — PASSO 1 de 3: estrutura nova
-- -----------------------------------------------------------------------------
-- O que este script faz:
--   * cria uma tabela por tipo de dado (filmes, links, editores, idiomas,
--     histórico e configuração) no lugar do registro único em JSON;
--   * liga o RLS em todas elas e define quem pode ler/criar/alterar/apagar;
--   * cria um gatilho que verifica, NO SERVIDOR, quais campos cada função
--     (admin / chefe / editor) pode alterar;
--   * cria as funções (RPC) usadas pelo painel para operações em várias
--     linhas ao mesmo tempo (novo filme, concluir filme, reordenar fila,
--     importar backup);
--   * adiciona as tabelas novas ao Realtime do Supabase.
--
-- O que este script NÃO faz:
--   * não altera nem apaga a tabela antiga `editor_panel_shared_data`
--     (ela continua sendo o backup da versão 1);
--   * não altera a tabela `station_user_access` (só a lê).
--
-- É seguro rodar com a versão 1 do painel ainda no ar: nada do que ela usa
-- é modificado. Rode no SQL Editor do Supabase. Tudo roda numa transação:
-- se algo falhar, nada é aplicado.
-- =============================================================================

begin;

-- -----------------------------------------------------------------------------
-- Funções de permissão
-- -----------------------------------------------------------------------------

-- Função do usuário logado. Usuário autenticado sem linha em
-- station_user_access é tratado como 'editor' (mesmo comportamento do painel).
create or replace function public.station_role()
returns text
language sql
stable
security definer
set search_path = public
as $$
  select case
    when auth.uid() is null then null
    else coalesce(
      (select a.role from public.station_user_access a where a.user_id = auth.uid() limit 1),
      'editor'
    )
  end
$$;

create or replace function public.station_is_admin()
returns boolean language sql stable set search_path = public
as $$ select coalesce(public.station_role() = 'admin', false) $$;

create or replace function public.station_is_manager()
returns boolean language sql stable set search_path = public
as $$ select coalesce(public.station_role() in ('admin', 'chief'), false) $$;

-- -----------------------------------------------------------------------------
-- Tabelas
-- -----------------------------------------------------------------------------

create table public.station_movies (
  id          text primary key default gen_random_uuid()::text,
  position    integer not null default 0,
  nome        text not null default '' check (char_length(nome) <= 300),
  -- pôster em JPEG embutido (data URL), como na versão 1; limite ~3,7 MB
  poster      text not null default ''
              check (poster = '' or (char_length(poster) <= 5000000
                     and poster ~ '^data:image/jpe?g;base64,[A-Za-z0-9+/=]+$')),
  drive       text not null default '' check (char_length(drive) <= 2000),
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now(),
  updated_by  uuid
);

create table public.station_movie_links (
  id          text primary key default gen_random_uuid()::text,
  movie_id    text not null references public.station_movies(id) on delete cascade,
  position    integer not null default 0,
  type        text not null default 'LINK DOS ARQUIVOS' check (char_length(type) <= 100),
  url         text not null default '' check (char_length(url) <= 2000),
  -- [{ "id": "BR-51", "country": "BR", "name": "Português (BR) 5.1" }, ...]
  languages   jsonb not null default '[]'::jsonb check (jsonb_typeof(languages) = 'array'),
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now(),
  updated_by  uuid
);
create index station_movie_links_movie_idx on public.station_movie_links(movie_id);

-- Editor de uma etapa. Em Efeitos/Música o próprio editor É a tarefa
-- (inicio/entrega/urgencia/status). Em Vocal as tarefas ficam em
-- station_vocal_rows (uma por idioma).
create table public.station_editors (
  id          text primary key default gen_random_uuid()::text,
  movie_id    text not null references public.station_movies(id) on delete cascade,
  dept        text not null check (dept in ('vocal', 'efeitos', 'musica')),
  position    integer not null default 0,
  user_id     uuid,
  nome        text not null default '' check (char_length(nome) <= 200),
  inicio      text not null default '' check (inicio = '' or inicio ~ '^\d{4}-\d{2}-\d{2}$'),
  entrega     text not null default '' check (entrega = '' or entrega ~ '^\d{4}-\d{2}-\d{2}$'),
  urgencia    text not null default 'media' check (urgencia in ('baixa', 'media', 'alta')),
  status      text not null default 'pendente' check (status in ('pendente', 'fazendo', 'concluido')),
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now(),
  updated_by  uuid
);
create index station_editors_movie_idx on public.station_editors(movie_id);
create index station_editors_user_idx on public.station_editors(user_id);

create table public.station_vocal_rows (
  id              text primary key default gen_random_uuid()::text,
  editor_id       text not null references public.station_editors(id) on delete cascade,
  position        integer not null default 0,
  idioma          text not null default '' check (char_length(idioma) <= 100),
  inicio          text not null default '' check (inicio = '' or inicio ~ '^\d{4}-\d{2}-\d{2}$'),
  entrega         text not null default '' check (entrega = '' or entrega ~ '^\d{4}-\d{2}-\d{2}$'),
  urgencia        text not null default 'media' check (urgencia in ('baixa', 'media', 'alta')),
  status          text not null default 'pendente' check (status in ('pendente', 'fazendo', 'concluido')),
  revisor         text not null default '' check (char_length(revisor) <= 200),
  status_revisao  text not null default 'pendente'
                  check (status_revisao in ('pendente', 'andamento', 'revisado', 'erro')),
  created_at      timestamptz not null default now(),
  updated_at      timestamptz not null default now(),
  updated_by      uuid
);
create index station_vocal_rows_editor_idx on public.station_vocal_rows(editor_id);

create table public.station_completed_movies (
  id            text primary key default gen_random_uuid()::text,
  nome          text not null default '',
  concluido_em  timestamptz not null default now(),
  -- [{ "idioma": "...", "editor": "...", "revisor": "..." }, ...]
  entries       jsonb not null default '[]'::jsonb check (jsonb_typeof(entries) = 'array'),
  concluido_por uuid
);

-- Configuração compartilhada (uma única linha): qual filme está "em produção".
create table public.station_settings (
  id                  integer primary key default 1 check (id = 1),
  production_movie_id text references public.station_movies(id) on delete set null,
  updated_at          timestamptz not null default now(),
  updated_by          uuid
);
insert into public.station_settings (id) values (1);

-- Dono de um editor (usado pelo RLS e pelo gatilho das linhas de idioma).
create or replace function public.station_editor_owner(p_editor_id text)
returns uuid language sql stable security definer set search_path = public
as $$ select e.user_id from public.station_editors e where e.id = p_editor_id $$;

-- -----------------------------------------------------------------------------
-- Gatilhos
-- -----------------------------------------------------------------------------

-- Carimbo de quem/quando alterou (movies, links, settings).
create or replace function public.station_touch()
returns trigger language plpgsql set search_path = public
as $$
begin
  new.updated_at := now();
  new.updated_by := auth.uid();
  return new;
end
$$;

create trigger station_movies_touch before update on public.station_movies
  for each row execute function public.station_touch();
create trigger station_movie_links_touch before update on public.station_movie_links
  for each row execute function public.station_touch();
create trigger station_settings_touch before update on public.station_settings
  for each row execute function public.station_touch();

-- Regras de alteração de tarefas (editores e linhas de idioma).
--   admin  : pode alterar tudo
--   chief  : idioma -> urgencia, revisor, status_revisao, status
--            editor -> user_id, nome, urgencia, status  (atribuição + tarefa)
--            NÃO altera datas
--   editor : só as PRÓPRIAS tarefas, e só inicio, entrega e status
-- Ao marcar status = 'concluido', a data de entrega vira a data de hoje
-- (feito aqui no servidor, para valer também para o chefe, que não pode
-- alterar datas diretamente).
-- Sem usuário (auth.uid() nulo) = SQL Editor / service role: sem restrição.
create or replace function public.station_guard_task_update()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid     uuid := auth.uid();
  v_role    text := public.station_role();
  v_owner   uuid;
  v_allowed text[];
  v_changed text[];
begin
  if v_uid is not null and v_role <> 'admin' then
    if v_role = 'chief' then
      if tg_table_name = 'station_vocal_rows' then
        v_allowed := array['urgencia', 'revisor', 'status_revisao', 'status'];
      else
        v_allowed := array['user_id', 'nome', 'urgencia', 'status'];
      end if;
    else
      if tg_table_name = 'station_vocal_rows' then
        v_owner := public.station_editor_owner(old.editor_id);
      else
        v_owner := old.user_id;
      end if;
      if v_owner is distinct from v_uid then
        raise exception 'Sem permissão: esta tarefa não pertence a você.'
          using errcode = '42501';
      end if;
      v_allowed := array['inicio', 'entrega', 'status'];
    end if;

    select array_agg(n.key order by n.key)
      into v_changed
      from jsonb_each(to_jsonb(new)) n
     where not (n.key = any (v_allowed || array['updated_at', 'updated_by']))
       and n.value is distinct from (to_jsonb(old) -> n.key);

    if v_changed is not null then
      raise exception 'Sem permissão para alterar: %', array_to_string(v_changed, ', ')
        using errcode = '42501';
    end if;
  end if;

  if new.status = 'concluido' and old.status is distinct from 'concluido' then
    new.entrega := to_char((now() at time zone 'America/Sao_Paulo')::date, 'YYYY-MM-DD');
  end if;

  new.updated_at := now();
  new.updated_by := v_uid;
  return new;
end
$$;

create trigger station_editors_guard before update on public.station_editors
  for each row execute function public.station_guard_task_update();
create trigger station_vocal_rows_guard before update on public.station_vocal_rows
  for each row execute function public.station_guard_task_update();

-- -----------------------------------------------------------------------------
-- RLS
-- -----------------------------------------------------------------------------

alter table public.station_movies           enable row level security;
alter table public.station_movie_links      enable row level security;
alter table public.station_editors          enable row level security;
alter table public.station_vocal_rows       enable row level security;
alter table public.station_completed_movies enable row level security;
alter table public.station_settings         enable row level security;

-- Visitantes não logados não têm nenhum acesso.
revoke all on public.station_movies, public.station_movie_links, public.station_editors,
              public.station_vocal_rows, public.station_completed_movies, public.station_settings
  from anon;
grant select, insert, update, delete on
  public.station_movies, public.station_movie_links, public.station_editors,
  public.station_vocal_rows
  to authenticated;
grant select on public.station_completed_movies to authenticated;
grant select, update on public.station_settings to authenticated;

-- Leitura: qualquer usuário logado.
create policy station_movies_select           on public.station_movies           for select to authenticated using (true);
create policy station_movie_links_select      on public.station_movie_links      for select to authenticated using (true);
create policy station_editors_select          on public.station_editors          for select to authenticated using (true);
create policy station_vocal_rows_select       on public.station_vocal_rows       for select to authenticated using (true);
create policy station_completed_movies_select on public.station_completed_movies for select to authenticated using (true);
create policy station_settings_select         on public.station_settings         for select to authenticated using (true);

-- Filmes: criados pela função station_create_movie (chefe/admin);
-- dados do filme (nome, pôster, drive) e exclusão: só admin.
create policy station_movies_update on public.station_movies for update to authenticated
  using (public.station_is_admin()) with check (public.station_is_admin());
create policy station_movies_delete on public.station_movies for delete to authenticated
  using (public.station_is_admin());

-- Links do filme: só admin.
create policy station_movie_links_insert on public.station_movie_links for insert to authenticated
  with check (public.station_is_admin());
create policy station_movie_links_update on public.station_movie_links for update to authenticated
  using (public.station_is_admin()) with check (public.station_is_admin());
create policy station_movie_links_delete on public.station_movie_links for delete to authenticated
  using (public.station_is_admin());

-- Editores: chefe/admin criam; só admin apaga; alteração: chefe/admin ou o
-- próprio editor (os campos permitidos são conferidos pelo gatilho).
create policy station_editors_insert on public.station_editors for insert to authenticated
  with check (public.station_is_manager());
create policy station_editors_update on public.station_editors for update to authenticated
  using (public.station_is_manager() or user_id = auth.uid())
  with check (true);
create policy station_editors_delete on public.station_editors for delete to authenticated
  using (public.station_is_admin());

-- Linhas de idioma (Vocal): mesmo esquema dos editores.
create policy station_vocal_rows_insert on public.station_vocal_rows for insert to authenticated
  with check (public.station_is_manager());
create policy station_vocal_rows_update on public.station_vocal_rows for update to authenticated
  using (public.station_is_manager() or public.station_editor_owner(editor_id) = auth.uid())
  with check (true);
create policy station_vocal_rows_delete on public.station_vocal_rows for delete to authenticated
  using (public.station_is_admin());

-- Filme em produção: chefe/admin.
create policy station_settings_update on public.station_settings for update to authenticated
  using (public.station_is_manager()) with check (public.station_is_manager());

-- Histórico: escrito só pelas funções abaixo (sem política de escrita).

-- -----------------------------------------------------------------------------
-- Funções chamadas pelo painel (RPC)
-- -----------------------------------------------------------------------------

-- Novo filme no topo da fila, com 7 editores em cada etapa.
create or replace function public.station_create_movie()
returns text
language plpgsql
security definer
set search_path = public
as $$
declare
  v_id   text := gen_random_uuid()::text;
  v_pos  integer;
  v_dept text;
  i      integer;
begin
  if not public.station_is_manager() then
    raise exception 'Sem permissão para criar filmes.' using errcode = '42501';
  end if;
  select coalesce(min(position), 0) - 1 into v_pos from public.station_movies;
  insert into public.station_movies (id, position) values (v_id, v_pos);
  foreach v_dept in array array['vocal', 'efeitos', 'musica'] loop
    for i in 1..7 loop
      insert into public.station_editors (movie_id, dept, position, nome)
      values (v_id, v_dept, i, 'Editor ' || i);
    end loop;
  end loop;
  return v_id;
end
$$;

-- Conclui um filme: grava o histórico (idioma/editor/revisor) e remove o
-- filme da produção, tudo numa única transação.
create or replace function public.station_complete_movie(p_movie_id text)
returns text
language plpgsql
security definer
set search_path = public
as $$
declare
  v_nome    text;
  v_entries jsonb;
  v_id      text := gen_random_uuid()::text;
begin
  if not public.station_is_manager() then
    raise exception 'Sem permissão para concluir filmes.' using errcode = '42501';
  end if;

  select nome into v_nome from public.station_movies where id = p_movie_id for update;
  if not found then
    raise exception 'Filme não encontrado (talvez já tenha sido concluído).' using errcode = 'P0002';
  end if;

  select coalesce(jsonb_agg(jsonb_build_object(
           'idioma',  coalesce(nullif(r.idioma, ''), 'Não informado'),
           'editor',  coalesce(nullif(e.nome, ''), 'Não informado'),
           'revisor', coalesce(nullif(r.revisor, ''), 'Não informado'))
         order by e.position, e.id, r.position, r.id), '[]'::jsonb)
    into v_entries
    from public.station_editors e
    join public.station_vocal_rows r on r.editor_id = e.id
   where e.movie_id = p_movie_id and e.dept = 'vocal';

  if jsonb_array_length(v_entries) = 0 then
    v_entries := '[{"idioma":"Não informado","editor":"Não informado","revisor":"Não informado"}]'::jsonb;
  end if;

  insert into public.station_completed_movies (id, nome, concluido_em, entries, concluido_por)
  values (v_id, coalesce(nullif(v_nome, ''), 'Sem título'), now(), v_entries, auth.uid());

  delete from public.station_movies where id = p_movie_id;
  return v_id;
end
$$;

-- Reordena a fila de filmes (lista completa de ids na nova ordem).
create or replace function public.station_reorder_movies(p_ids text[])
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if not public.station_is_manager() then
    raise exception 'Sem permissão para reordenar a fila.' using errcode = '42501';
  end if;
  update public.station_movies m
     set position = o.ord, updated_at = now(), updated_by = auth.uid()
    from unnest(p_ids) with ordinality as o(id, ord)
   where m.id = o.id;
end
$$;

-- Importa um backup no formato da versão 1/2.0 (o mesmo do botão
-- "Exportar dados"), SUBSTITUINDO todos os dados atuais.
-- Uso interno: não é exposta ao painel diretamente (ver station_import).
create or replace function public.station_import_internal(p jsonb)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_movie    jsonb;  v_mpos  bigint;  v_mid  text;
  v_link     jsonb;  v_lpos  bigint;  v_lid  text;
  v_editor   jsonb;  v_epos  bigint;  v_eid  text;
  v_row      jsonb;  v_rpos  bigint;  v_rid  text;
  v_done     jsonb;  v_dpos  bigint;
  v_dept     text;
  v_uid      uuid;
  v_poster   text;
  v_prod_old text := p ->> 'productionMovieId';
  v_prod_new text;
  v_langs    jsonb;
  v_when     timestamptz;
  n_movies int := 0; n_links int := 0; n_editors int := 0; n_rows int := 0;
  n_done int := 0; n_posters_dropped int := 0; n_users_matched int := 0;
begin
  if p is null or jsonb_typeof(p -> 'movies') is distinct from 'array' then
    raise exception 'Backup inválido: campo "movies" ausente.' using errcode = '22023';
  end if;

  update public.station_settings set production_movie_id = null where id = 1;
  delete from public.station_movies;            -- apaga links/editores/idiomas em cascata
  delete from public.station_completed_movies;

  for v_movie, v_mpos in
    select value, ordinality from jsonb_array_elements(p -> 'movies') with ordinality
  loop
    continue when jsonb_typeof(v_movie) <> 'object';

    v_mid := nullif(v_movie ->> 'id', '');
    if v_mid is null or exists (select 1 from public.station_movies where id = v_mid) then
      v_mid := gen_random_uuid()::text;
    end if;
    if v_prod_old is not null and v_movie ->> 'id' = v_prod_old then
      v_prod_new := v_mid;
    end if;

    v_poster := coalesce(v_movie ->> 'poster', '');
    if v_poster <> '' and not (char_length(v_poster) <= 5000000
        and v_poster ~ '^data:image/jpe?g;base64,[A-Za-z0-9+/=]+$') then
      v_poster := '';
      n_posters_dropped := n_posters_dropped + 1;
    end if;

    insert into public.station_movies (id, position, nome, poster, drive)
    values (v_mid, v_mpos,
            left(coalesce(v_movie ->> 'nome', ''), 300),
            v_poster,
            left(coalesce(v_movie ->> 'drive', ''), 2000));
    n_movies := n_movies + 1;

    if jsonb_typeof(v_movie -> 'movieLinks') = 'array' then
      for v_link, v_lpos in
        select value, ordinality from jsonb_array_elements(v_movie -> 'movieLinks') with ordinality
      loop
        continue when jsonb_typeof(v_link) <> 'object';
        v_lid := nullif(v_link ->> 'id', '');
        if v_lid is null or exists (select 1 from public.station_movie_links where id = v_lid) then
          v_lid := gen_random_uuid()::text;
        end if;
        v_langs := case when jsonb_typeof(v_link -> 'languages') = 'array'
                        then v_link -> 'languages' else '[]'::jsonb end;
        insert into public.station_movie_links (id, movie_id, position, type, url, languages)
        values (v_lid, v_mid, v_lpos,
                left(coalesce(nullif(v_link ->> 'type', ''), 'LINK DOS ARQUIVOS'), 100),
                left(coalesce(v_link ->> 'url', ''), 2000),
                v_langs);
        n_links := n_links + 1;
      end loop;
    end if;

    foreach v_dept in array array['vocal', 'efeitos', 'musica'] loop
      continue when jsonb_typeof(v_movie -> 'depts' -> v_dept -> 'editors') is distinct from 'array';
      for v_editor, v_epos in
        select value, ordinality
          from jsonb_array_elements(v_movie -> 'depts' -> v_dept -> 'editors') with ordinality
      loop
        continue when jsonb_typeof(v_editor) <> 'object';
        v_eid := nullif(v_editor ->> 'id', '');
        if v_eid is null or exists (select 1 from public.station_editors where id = v_eid) then
          v_eid := gen_random_uuid()::text;
        end if;

        v_uid := null;
        if (v_editor ->> 'user_id') ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' then
          v_uid := (v_editor ->> 'user_id')::uuid;
        elsif coalesce(trim(v_editor ->> 'nome'), '') <> '' then
          -- vincula pelo nome quando existe exatamente um usuário com esse nome
          select min(a.user_id::text)::uuid into v_uid
            from public.station_user_access a
           where lower(trim(a.editor_name)) = lower(trim(v_editor ->> 'nome'))
          having count(*) = 1;
          if v_uid is not null then n_users_matched := n_users_matched + 1; end if;
        end if;

        insert into public.station_editors
          (id, movie_id, dept, position, user_id, nome, inicio, entrega, urgencia, status)
        values (
          v_eid, v_mid, v_dept, v_epos, v_uid,
          left(coalesce(v_editor ->> 'nome', ''), 200),
          case when v_dept <> 'vocal' and (v_editor ->> 'inicio') ~ '^\d{4}-\d{2}-\d{2}$'
               then v_editor ->> 'inicio' else '' end,
          case when v_dept <> 'vocal' and (v_editor ->> 'entrega') ~ '^\d{4}-\d{2}-\d{2}$'
               then v_editor ->> 'entrega' else '' end,
          case when v_editor ->> 'urgencia' in ('baixa', 'media', 'alta')
               then v_editor ->> 'urgencia' else 'media' end,
          case when v_editor ->> 'status' in ('pendente', 'fazendo', 'concluido')
               then v_editor ->> 'status' else 'pendente' end
        );
        n_editors := n_editors + 1;

        if v_dept = 'vocal' and jsonb_typeof(v_editor -> 'idiomas') = 'array' then
          for v_row, v_rpos in
            select value, ordinality from jsonb_array_elements(v_editor -> 'idiomas') with ordinality
          loop
            -- formato muito antigo: idiomas como lista de textos
            if jsonb_typeof(v_row) = 'string' then
              v_row := jsonb_build_object('idioma', v_row #>> '{}');
            end if;
            continue when jsonb_typeof(v_row) <> 'object';
            v_rid := nullif(v_row ->> 'id', '');
            if v_rid is null or exists (select 1 from public.station_vocal_rows where id = v_rid) then
              v_rid := gen_random_uuid()::text;
            end if;
            insert into public.station_vocal_rows
              (id, editor_id, position, idioma, inicio, entrega, urgencia, status, revisor, status_revisao)
            values (
              v_rid, v_eid, v_rpos,
              left(coalesce(v_row ->> 'idioma', ''), 100),
              case when (v_row ->> 'inicio') ~ '^\d{4}-\d{2}-\d{2}$' then v_row ->> 'inicio' else '' end,
              case when (v_row ->> 'entrega') ~ '^\d{4}-\d{2}-\d{2}$' then v_row ->> 'entrega' else '' end,
              case when v_row ->> 'urgencia' in ('baixa', 'media', 'alta') then v_row ->> 'urgencia' else 'media' end,
              case when v_row ->> 'status' in ('pendente', 'fazendo', 'concluido') then v_row ->> 'status' else 'pendente' end,
              left(coalesce(v_row ->> 'revisor', ''), 200),
              case when v_row ->> 'statusRevisao' in ('pendente', 'andamento', 'revisado', 'erro')
                   then v_row ->> 'statusRevisao' else 'pendente' end
            );
            n_rows := n_rows + 1;
          end loop;
        end if;
      end loop;
    end loop;
  end loop;

  if jsonb_typeof(p -> 'completedMovies') = 'array' then
    for v_done, v_dpos in
      select value, ordinality from jsonb_array_elements(p -> 'completedMovies') with ordinality
    loop
      continue when jsonb_typeof(v_done) <> 'object';
      begin
        v_when := (v_done ->> 'concluidoEm')::timestamptz;
      exception when others then
        v_when := null;
      end;
      insert into public.station_completed_movies (id, nome, concluido_em, entries)
      values (
        gen_random_uuid()::text,
        coalesce(nullif(v_done ->> 'nome', ''), 'Sem título'),
        -- sem data válida: mantém a ordem original, do mais novo ao mais antigo
        coalesce(v_when, timestamptz '2000-01-01' - make_interval(secs => v_dpos)),
        case when jsonb_typeof(v_done -> 'entries') = 'array' then v_done -> 'entries' else '[]'::jsonb end
      );
      n_done := n_done + 1;
    end loop;
  end if;

  update public.station_settings set production_movie_id = v_prod_new where id = 1;

  return jsonb_build_object(
    'filmes', n_movies, 'links', n_links, 'editores', n_editors,
    'idiomas', n_rows, 'historico', n_done,
    'posteres_descartados', n_posters_dropped,
    'editores_vinculados_pelo_nome', n_users_matched
  );
end
$$;

-- Versão exposta ao painel: só administrador.
create or replace function public.station_import(p jsonb)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
begin
  if not public.station_is_admin() then
    raise exception 'Somente o administrador pode importar dados.' using errcode = '42501';
  end if;
  return public.station_import_internal(p);
end
$$;

revoke all on function public.station_import_internal(jsonb) from public, anon, authenticated;
revoke all on function public.station_create_movie()             from public, anon;
revoke all on function public.station_complete_movie(text)       from public, anon;
revoke all on function public.station_reorder_movies(text[])     from public, anon;
revoke all on function public.station_import(jsonb)              from public, anon;
grant execute on function public.station_create_movie()          to authenticated;
grant execute on function public.station_complete_movie(text)    to authenticated;
grant execute on function public.station_reorder_movies(text[])  to authenticated;
grant execute on function public.station_import(jsonb)           to authenticated;

-- -----------------------------------------------------------------------------
-- Realtime: avisa os navegadores abertos quando algo muda
-- -----------------------------------------------------------------------------
do $$
begin
  if exists (select 1 from pg_publication where pubname = 'supabase_realtime') then
    alter publication supabase_realtime add table
      public.station_movies, public.station_movie_links, public.station_editors,
      public.station_vocal_rows, public.station_completed_movies, public.station_settings;
  else
    raise notice 'Publicação supabase_realtime não encontrada: ative o Realtime para as tabelas station_* no painel do Supabase.';
  end if;
end
$$;

commit;
