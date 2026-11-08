-- =============================================================================
-- Estação de Editores 2.0 — PASSO 2 de 3: copiar os dados da versão 1
-- -----------------------------------------------------------------------------
-- Copia o conteúdo do registro único `editor_panel_shared_data` (id = 1)
-- para as tabelas novas criadas no passo 1.
--
-- * A tabela antiga NÃO é alterada: continua servindo de backup.
-- * Por segurança, o script se recusa a rodar se as tabelas novas já tiverem
--   filmes (para não apagar trabalho feito na 2.0). Para refazer a cópia de
--   propósito, troque `v_forcar := false` por `true`.
-- * Rode este passo IMEDIATAMENTE antes de publicar o index.html novo, para
--   que nada feito na versão 1 entre a cópia e a troca seja perdido.
-- * O resultado (quantidades copiadas) aparece em "Messages"/"Notices".
-- =============================================================================

do $$
declare
  v_forcar    boolean := false;
  v_payload   jsonb;
  v_resultado jsonb;
begin
  select payload into v_payload from public.editor_panel_shared_data where id = 1;
  if v_payload is null then
    raise exception 'Registro id = 1 não encontrado em editor_panel_shared_data.';
  end if;

  if not v_forcar and exists (select 1 from public.station_movies) then
    raise exception 'As tabelas novas já têm filmes. Nada foi alterado. (Para refazer, use v_forcar := true.)';
  end if;

  v_resultado := public.station_import_internal(v_payload);
  raise notice 'Cópia concluída: %', v_resultado;
end
$$;

-- Conferência: compare com o que aparece no painel antigo.
select
  (select count(*) from public.station_movies)           as filmes,
  (select count(*) from public.station_movie_links)      as links,
  (select count(*) from public.station_editors)          as editores,
  (select count(*) from public.station_vocal_rows)       as idiomas,
  (select count(*) from public.station_completed_movies) as historico,
  (select count(*) from public.station_editors where user_id is not null) as editores_com_usuario;
