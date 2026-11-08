-- Executa cada comando como um usuário, desfaz tudo no final e compara com o esperado.
create or replace function pg_temp.t(p_desc text, p_user text, p_sql text, p_expect boolean)
returns text language plpgsql as $f$
declare n bigint; ok boolean; msg text := '';
begin
  begin
    if p_user = 'anon' then
      perform set_config('request.jwt.claims', '{}', true);
      execute 'set local role anon';
    else
      perform set_config('request.jwt.claims', json_build_object('sub', p_user)::text, true);
      execute 'set local role authenticated';
    end if;
    execute p_sql;
    get diagnostics n = row_count;
    raise exception using errcode = 'Z0001', message = n::text;
  exception
    when sqlstate 'Z0001' then ok := (sqlerrm::bigint > 0); msg := sqlerrm || ' linha(s)';
    when others then ok := false; msg := sqlerrm;
  end;
  return (case when ok = p_expect then 'PASS' else '**FAIL**' end) || ' | ' || p_desc || ' | ' || msg;
end $f$;

\set ADM 'aaaaaaaa-0000-0000-0000-000000000001'
\set CHF 'cccccccc-0000-0000-0000-000000000001'
\set ANA 'eeeeeeee-0000-0000-0000-000000000001'
\set BRU 'eeeeeeee-0000-0000-0000-000000000002'
\set SEM 'ffffffff-0000-0000-0000-000000000009'

select r from (values
 -- visitante sem login
 (pg_temp.t('anon não lê filmes', 'anon', 'select * from station_movies', false)),
 (pg_temp.t('anon não lê idiomas', 'anon', 'select * from station_vocal_rows', false)),
 (pg_temp.t('anon não cria filme', 'anon', 'select station_create_movie()', false)),
 -- editor (Ana é dona de e1/r1/r2 e s3)
 (pg_temp.t('editor lê filmes', :'ANA', 'select * from station_movies', true)),
 (pg_temp.t('editor muda status da própria linha', :'ANA', $$update station_vocal_rows set status='concluido' where id='r1'$$, true)),
 (pg_temp.t('editor muda datas da própria linha', :'ANA', $$update station_vocal_rows set inicio='2026-11-05', entrega='2026-11-20' where id='r1'$$, true)),
 (pg_temp.t('editor NÃO muda urgência da própria linha', :'ANA', $$update station_vocal_rows set urgencia='baixa' where id='r1'$$, false)),
 (pg_temp.t('editor NÃO muda revisor', :'ANA', $$update station_vocal_rows set revisor='eu' where id='r1'$$, false)),
 (pg_temp.t('editor NÃO move linha p/ outro editor', :'ANA', $$update station_vocal_rows set editor_id='e2' where id='r1'$$, false)),
 (pg_temp.t('editor NÃO muda linha de outro editor', :'ANA', $$update station_vocal_rows set status='concluido' where id='r3'$$, false)),
 (pg_temp.t('editor muda status da própria tarefa (Música)', :'ANA', $$update station_editors set status='fazendo' where id='s3'$$, true)),
 (pg_temp.t('editor NÃO muda tarefa de outro (Efeitos)', :'ANA', $$update station_editors set status='fazendo' where id='s1'$$, false)),
 (pg_temp.t('editor NÃO se reatribui (user_id)', :'ANA', $$update station_editors set user_id=null where id='s3'$$, false)),
 (pg_temp.t('editor NÃO muda nome do filme', :'ANA', $$update station_movies set nome='hack' where id='m1'$$, false)),
 (pg_temp.t('editor NÃO apaga filme', :'ANA', $$delete from station_movies where id='m1'$$, false)),
 (pg_temp.t('editor NÃO apaga linha própria', :'ANA', $$delete from station_vocal_rows where id='r1'$$, false)),
 (pg_temp.t('editor NÃO cria linha', :'ANA', $$insert into station_vocal_rows(editor_id,idioma) values ('e1','Grego 5.1')$$, false)),
 (pg_temp.t('editor NÃO cria filme', :'ANA', 'select station_create_movie()', false)),
 (pg_temp.t('editor NÃO conclui filme', :'ANA', $$select station_complete_movie('m1')$$, false)),
 (pg_temp.t('editor NÃO reordena fila', :'ANA', $$select station_reorder_movies(array['m2','m1'])$$, false)),
 (pg_temp.t('editor NÃO muda filme em produção', :'ANA', $$update station_settings set production_movie_id='m1'$$, false)),
 (pg_temp.t('editor NÃO importa', :'ANA', $$select station_import('{"movies":[]}')$$, false)),
 (pg_temp.t('editor NÃO chama import interno', :'ANA', $$select station_import_internal('{"movies":[]}')$$, false)),
 (pg_temp.t('editor NÃO escreve histórico', :'ANA', $$insert into station_completed_movies(nome) values ('x')$$, false)),
 (pg_temp.t('editor NÃO mexe em links', :'ANA', $$update station_movie_links set url='x' where id='L1'$$, false)),
 (pg_temp.t('usuário sem perfil = editor sem tarefas', :'SEM', $$update station_vocal_rows set status='fazendo' where id='r1'$$, false)),
 -- chefe
 (pg_temp.t('chefe muda urgência/revisor/statusRevisão/status', :'CHF', $$update station_vocal_rows set urgencia='baixa', revisor='Rev2', status_revisao='erro', status='fazendo' where id='r3'$$, true)),
 (pg_temp.t('chefe NÃO muda datas', :'CHF', $$update station_vocal_rows set inicio='2026-01-01' where id='r3'$$, false)),
 (pg_temp.t('chefe atribui editor (user_id + nome)', :'CHF', $$update station_editors set user_id='eeeeeeee-0000-0000-0000-000000000002', nome='Bruno' where id='e3'$$, true)),
 (pg_temp.t('chefe NÃO muda datas em Efeitos', :'CHF', $$update station_editors set entrega='2026-01-01' where id='s1'$$, false)),
 (pg_temp.t('chefe NÃO muda departamento do editor', :'CHF', $$update station_editors set dept='musica' where id='s1'$$, false)),
 (pg_temp.t('chefe cria editor', :'CHF', $$insert into station_editors(movie_id,dept,position,nome) values ('m1','efeitos',9,'Novo')$$, true)),
 (pg_temp.t('chefe cria linha de idioma', :'CHF', $$insert into station_vocal_rows(editor_id,idioma) values ('e1','Grego 5.1')$$, true)),
 (pg_temp.t('chefe NÃO apaga linha', :'CHF', $$delete from station_vocal_rows where id='r1'$$, false)),
 (pg_temp.t('chefe NÃO apaga editor', :'CHF', $$delete from station_editors where id='e1'$$, false)),
 (pg_temp.t('chefe NÃO muda nome/pôster do filme', :'CHF', $$update station_movies set nome='x' where id='m1'$$, false)),
 (pg_temp.t('chefe cria filme', :'CHF', 'select station_create_movie()', true)),
 (pg_temp.t('chefe conclui filme', :'CHF', $$select station_complete_movie('m1')$$, true)),
 (pg_temp.t('chefe reordena fila', :'CHF', $$select station_reorder_movies(array['m2','m1'])$$, true)),
 (pg_temp.t('chefe muda filme em produção', :'CHF', $$update station_settings set production_movie_id='m1'$$, true)),
 (pg_temp.t('chefe NÃO importa', :'CHF', $$select station_import('{"movies":[]}')$$, false)),
 (pg_temp.t('chefe NÃO mexe em links', :'CHF', $$insert into station_movie_links(movie_id,url) values ('m1','x')$$, false)),
 -- admin
 (pg_temp.t('admin muda tudo numa linha', :'ADM', $$update station_vocal_rows set inicio='2026-01-01', urgencia='alta', editor_id='e2' where id='r1'$$, true)),
 (pg_temp.t('admin muda nome do filme', :'ADM', $$update station_movies set nome='Novo nome' where id='m1'$$, true)),
 (pg_temp.t('admin cria link', :'ADM', $$insert into station_movie_links(movie_id,url) values ('m1','x')$$, true)),
 (pg_temp.t('admin apaga filme', :'ADM', $$delete from station_movies where id='m1'$$, true)),
 (pg_temp.t('admin importa', :'ADM', $$select station_import('{"movies":[]}')$$, true)),
 -- validação de dados (mesmo para admin)
 (pg_temp.t('pôster não-JPEG recusado', :'ADM', $$update station_movies set poster='data:text/html;base64,AAAA' where id='m1'$$, false)),
 (pg_temp.t('pôster com aspas recusado', :'ADM', $$update station_movies set poster='data:image/jpeg;base64,A" onerror="x' where id='m1'$$, false)),
 (pg_temp.t('urgência inválida recusada', :'ADM', $$update station_vocal_rows set urgencia='x" onmouseover="y' where id='r1'$$, false)),
 (pg_temp.t('data inválida recusada', :'ADM', $$update station_vocal_rows set inicio='amanhã' where id='r1'$$, false))
) v(r);
