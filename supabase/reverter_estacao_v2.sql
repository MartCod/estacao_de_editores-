-- =============================================================================
-- Estação de Editores 2.0 — REVERTER (voltar para a versão 1)
-- -----------------------------------------------------------------------------
-- 1. Volte o index.html da versão 1 no servidor.
-- 2. Rode este script.
--
-- ATENÇÃO: apaga as tabelas station_* e tudo o que foi feito nelas na 2.0.
-- Se quiser guardar esse trabalho, antes use "Exportar dados" na 2.0 e depois
-- "Importar dados" na versão 1 (o formato do arquivo é o mesmo).
-- O registro antigo `editor_panel_shared_data` volta a aceitar gravações.
-- =============================================================================

begin;

grant insert, update on public.editor_panel_shared_data to authenticated;

drop function if exists public.station_import(jsonb);
drop function if exists public.station_import_internal(jsonb);
drop function if exists public.station_reorder_movies(text[]);
drop function if exists public.station_complete_movie(text);
drop function if exists public.station_create_movie();

drop table if exists public.station_settings;
drop table if exists public.station_completed_movies;
drop table if exists public.station_vocal_rows;
drop table if exists public.station_editors;
drop table if exists public.station_movie_links;
drop table if exists public.station_movies;

drop function if exists public.station_guard_task_update();
drop function if exists public.station_touch();
drop function if exists public.station_editor_owner(text);
drop function if exists public.station_is_manager();
drop function if exists public.station_is_admin();
drop function if exists public.station_role();

commit;
