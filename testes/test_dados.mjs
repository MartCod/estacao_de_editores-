// Testes da camada de dados (itens 1, 2, 12 e 13 da auditoria).
import { execFileSync } from 'node:child_process';
import { openBrowser, sqlAdmin, sleep, closeAll, USERS } from './harness.mjs';

const RESET = new URL('./reset_db.sh', import.meta.url).pathname;
let pass = 0, fail = 0;
function ok(cond, desc, extra = ''){
  if(cond){ pass++; console.log('PASS |', desc); }
  else { fail++; console.log('**FAIL** |', desc, extra ? '| ' + extra : ''); }
}
const q = sql => sqlAdmin(sql);

execFileSync(RESET);

// ---------------------------------------------------------------- carregamento
const admin = await openBrowser('admin', { user: USERS.admin });
ok(admin.elements.authOverlay.style.display === 'none', 'admin: login automático pela sessão salva e tela liberada');
ok(admin.eval('movies.length') === 2, 'admin: carrega os 2 filmes das tabelas novas');
ok(admin.html().includes('Filme Um') && admin.html().includes('Filme Dois'), 'admin: nomes dos filmes aparecem na tela');
ok(admin.eval("movies[0].depts.vocal.editors[0].idiomas.length") === 2, 'admin: idiomas do editor montados na estrutura da tela');
ok(admin.eval('productionMovieId') === 'm2', 'admin: filme em produção vem do servidor');
ok(admin.status().includes('Alterações salvas'), 'admin: indicador "Alterações salvas" após carregar', admin.status());

// ------------------------------------------------- item 12: navegação é local
admin.eval("switchDept('musica')");
admin.eval("selectMovie('m2')");
await admin.idle();
ok(!admin.log.some(l => /^(update|insert|rpc)/.test(l)), 'item 12: trocar aba/filme NÃO grava nada no servidor', admin.log.filter(l => /^(update|insert|rpc)/.test(l)).join(';'));
ok(JSON.parse(admin.ls.get('estacao_editores_ui_v2')).activeDept === 'musica', 'item 12: aba aberta fica salva só no navegador');
admin.eval("switchDept('vocal'); selectMovie('m1')");

// ---------------------------------- item 1: duas pessoas editando ao mesmo tempo
const chefe = await openBrowser('chefe', { user: USERS.chefe });
const ana = await openBrowser('ana', { user: USERS.ana });
// "Aba velha": Bruno abriu antes de todo mundo mexer e ficou parado.
const bruno = await openBrowser('bruno', { user: USERS.bruno, realtime: false });

ana.eval("updateLangRowField('m1','e1','r1','status','concluido')");
chefe.eval("updateLangRowField('m1','e2','r3','urgencia','alta')");
admin.eval("updateMovieField('m1','nome','Filme Um (editado)')");
await Promise.all([ana.idle(), chefe.idle(), admin.idle()]);
// a aba velha do Bruno agora faz uma alteração própria
bruno.eval("updateLangRowField('m1','e2','r3','status','fazendo')");
await bruno.idle();

const r = (await q(`select (select status from station_vocal_rows where id='r1') || ',' ||
  (select urgencia||'/'||status from station_vocal_rows where id='r3') || ',' ||
  (select nome from station_movies where id='m1')`));
ok(r === 'concluido,alta/fazendo,Filme Um (editado)', 'item 1: alterações de 4 pessoas convivem (nenhuma apagou a outra)', r);
ok(bruno.log.filter(l => l.startsWith('update')).length === 1 && bruno.log.some(l => l.startsWith('update station_vocal_rows where id = $Q$r3$Q$')),
   'item 1: a aba velha grava SÓ a linha que ela alterou', bruno.log.filter(l => l.startsWith('update')).join(';'));
const entrega = await q(`select entrega from station_vocal_rows where id='r1'`);
ok(/^\d{4}-\d{2}-\d{2}$/.test(entrega), 'concluir idioma preenche a data de entrega (servidor)', entrega);

// ---------------------------------------------------------- tempo real
await sleep(50);
ok(chefe.eval("store.rows.get('r1').status") === 'concluido', 'tempo real: chefe recebe a conclusão feita pela Ana');
ok(ana.eval("store.movies.get('m1').nome") === 'Filme Um (editado)', 'tempo real: Ana recebe o nome novo do filme');
ok(chefe.html().includes('Filme Um (editado)'), 'tempo real: tela do chefe redesenhada com o nome novo');

// ---------------------------------------------- item 2: permissões no servidor
const antes = await q(`select status from station_vocal_rows where id='r3'`);
ana.alerts.length = 0;
// tentativa "pelo console" de mudar a linha de outro editor, sem passar pela tela
ana.eval("patchRow('rows','r3',{ status:'concluido' })");
await ana.idle(); await sleep(100);
ok(await q(`select status from station_vocal_rows where id='r3'`) === antes, 'item 2: editor NÃO altera linha de outro editor nem pelo console');
ok(ana.alerts.some(a => /recusou/.test(a)), 'item 2: a pessoa é avisada da recusa', ana.alerts.join('|'));
ok(ana.eval("store.rows.get('r3').status") === antes, 'item 2: tela da Ana volta ao valor real do servidor');
ok(ana.status().includes('Erro ao salvar'), 'item 2: indicador mostra "Erro ao salvar"', ana.status());

const res = await ana.eval("supabaseClient.from('station_movies').update({ nome:'hack' }).eq('id','m1').select()");
ok(res.data && res.data.length === 0 && await q(`select nome from station_movies where id='m1'`) === 'Filme Um (editado)', 'item 2: editor NÃO renomeia filme direto pela API');
const res2 = await ana.eval("supabaseClient.from('station_movies').delete().eq('id','m1').select()");
ok(res2.data && res2.data.length === 0 && await q(`select count(*) from station_movies`) === '2', 'item 2: editor NÃO apaga filme direto pela API');
const res3 = await ana.eval("supabaseClient.from('editor_panel_shared_data').select('id')");
ok(true, 'info: tabela antiga continua existindo como backup (' + (res3.data ? res3.data.length : 0) + ' linha)');

// editor muda as próprias datas
ana.eval("updateLangRowField('m1','e1','r2','inicio','2026-12-01')");
await ana.idle();
ok(await q(`select inicio from station_vocal_rows where id='r2'`) === '2026-12-01', 'editor altera a data de início da própria linha');

// -------------------------------------- item 13: texto grava uma vez, só o campo
admin.log.length = 0;
for(const v of ['F', 'Fi', 'Fil', 'Film', 'Filme 1']){ admin.eval(`updateMovieField('m1','nome',${JSON.stringify(v)})`); await sleep(40); }
await admin.idle();
const updates = admin.log.filter(l => l.startsWith('update'));
ok(updates.length === 1, 'item 13: digitar 5 vezes gera 1 gravação', updates.length + ' gravações');
ok(await q(`select nome from station_movies where id='m1'`) === 'Filme 1', 'item 13: valor final gravado');

// ------------------------------------------------------- operações do chefe/admin
chefe.eval("addMovie()");
await chefe.idle(); await sleep(50);
ok(await q(`select count(*) from station_movies`) === '3', 'chefe cria filme novo (RPC)');
ok(await q(`select count(*) from station_editors e join station_movies m on m.id=e.movie_id where m.position=(select min(position) from station_movies)`) === '21', 'filme novo nasce com 7 editores em cada etapa');
const novoId = chefe.eval('activeId');
ok(chefe.eval('movies[0].id') === novoId, 'filme novo fica no topo e é aberto');

chefe.eval(`addLanguageRow(${JSON.stringify(novoId)}, movies[0].depts.vocal.editors[0].id, 'Grego 5.1')`);
await chefe.idle();
ok(await q(`select count(*) from station_vocal_rows where idioma='Grego 5.1'`) === '1', 'chefe adiciona idioma a um editor');
chefe.eval("switchDept('efeitos')");
chefe.eval(`addEditorRow(${JSON.stringify(novoId)})`);
await chefe.idle();
ok(await q(`select count(*) from station_editors where movie_id='${novoId}' and dept='efeitos'`) === '8', 'chefe adiciona editor na etapa Efeitos');

chefe.eval("setProductionMovie('m1')");
await chefe.idle();
ok(await q(`select production_movie_id from station_settings`) === 'm1', 'chefe muda o filme em produção');

admin.eval(`assignEditorUser('m1','e3','${USERS.bruno.id}')`);
await admin.idle();
ok(await q(`select user_id||'/'||nome from station_editors where id='e3'`) === `${USERS.bruno.id}/Bruno`, 'admin atribui usuário ao editor');

admin.eval("removeLangRow('m1','e2','r3')");
await admin.idle();
ok(await q(`select count(*) from station_vocal_rows where id='r3'`) === '0', 'admin remove idioma');

admin.eval("completeMovie('m1')");
await admin.idle(); await sleep(50);
ok(await q(`select count(*) from station_movies where id='m1'`) === '0', 'concluir filme tira da produção');
ok(await q(`select nome from station_completed_movies order by concluido_em desc limit 1`) === 'Filme 1', 'concluir filme grava o histórico');
ok(admin.eval('currentView') === 'history' && admin.html().includes('Filme 1'), 'histórico aparece na tela');
ok(await q(`select production_movie_id is null from station_settings`) === 't', 'filme em produção concluído: configuração volta para vazio');

// ------------------------------------------------------------- export / import
const exported = admin.eval('JSON.stringify({ movies, completedMovies, productionMovieId })');
const before = await q(`select count(*)||'/'||(select count(*) from station_editors)||'/'||(select count(*) from station_vocal_rows)||'/'||(select count(*) from station_completed_movies) from station_movies`);
const imp = await admin.eval(`callRpc('station_import', { p: ${exported} })`);
await admin.idle();
const after = await q(`select count(*)||'/'||(select count(*) from station_editors)||'/'||(select count(*) from station_vocal_rows)||'/'||(select count(*) from station_completed_movies) from station_movies`);
ok(imp && before === after, 'exportar → importar devolve os mesmos dados (filmes/editores/idiomas/histórico)', before + ' vs ' + after);
const impChefe = await chefe.eval(`callRpc('station_import', { p: { movies: [] } })`);
await chefe.idle();
ok(!impChefe && await q(`select count(*) from station_movies`) !== '0', 'chefe NÃO consegue importar (apagar tudo)');

// ------------------------------------------------------------- fallback sem tempo real
await q(`update station_movies set nome='Mudou por fora' where id='m2'`);
ok(bruno.eval("store.movies.get('m2').nome") !== 'Mudou por fora', 'sem tempo real: aba do Bruno ainda não sabe da mudança');
await bruno.eval('refetchAll()');
ok(bruno.eval("store.movies.get('m2').nome") === 'Mudou por fora', 'sem tempo real: recarga periódica traz a mudança');

console.log(`\n${pass} passaram, ${fail} falharam`);
closeAll();
process.exit(fail ? 1 : 0);
