-- =============================================================================
-- Estação de Editores 2.0 — PASSO 3 de 3: congelar a tabela da versão 1
-- -----------------------------------------------------------------------------
-- Rode SÓ DEPOIS que o index.html 2.0 estiver no ar e conferido.
--
-- Abas antigas (versão 1) que ficaram abertas em algum computador continuariam
-- gravando no registro antigo, e essas alterações não apareceriam na 2.0.
-- Este passo bloqueia a escrita nesse registro: a aba antiga passa a mostrar
-- "Erro ao salvar", sinal para a pessoa recarregar a página.
--
-- A leitura continua liberada (backup). Para desfazer:
--   grant insert, update on public.editor_panel_shared_data to authenticated;
-- =============================================================================

revoke insert, update, delete on public.editor_panel_shared_data from anon, authenticated;
