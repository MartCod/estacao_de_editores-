// Itens 6–11: comportamento das telas por perfil.
import { execFileSync } from 'node:child_process';
import { openBrowser, sqlAdmin, closeAll, USERS, sleep } from './harness.mjs';
let pass = 0, fail = 0;
const ok = (c, d, x = '') => { c ? pass++ : fail++; console.log(c ? 'PASS |' : '**FAIL** |', d, !c && x ? '| ' + x : ''); };
const only = (process.env.ITENS || '6,7,8,9,10,idiomas,11').split(',');
execFileSync(new URL('./reset_db.sh', import.meta.url).pathname);
const admin = await openBrowser('admin', { user: USERS.admin });
const chefe = await openBrowser('chefe', { user: USERS.chefe });
const ana = await openBrowser('ana', { user: USERS.ana });

if(only.includes('6')){
  ana.eval("selectMovie('m1'); switchDept('musica')");   // s3 (Música) é da Ana
  ok(/<select class="status-select"[^>]*updateSimpleEditorField/.test(ana.html()), 'item 6: editora vê o status da PRÓPRIA tarefa de Música editável');
  ana.eval("updateSimpleEditorField('m1','s3','status','fazendo')"); await ana.idle();
  ok(await sqlAdmin("select status from station_editors where id='s3'") === 'fazendo', 'item 6: e a alteração é gravada');
  ana.eval("switchDept('efeitos')");   // s1 é do Bruno
  ok(!/<select class="status-select"/.test(ana.html()), 'item 6: tarefa de outro editor continua só leitura');
}
if(only.includes('10')){
  chefe.eval("selectMovie('m1'); switchDept('efeitos')");
  ok(/editor-name-input inline[\s\S]*?assignEditorUser/.test(chefe.html()), 'item 10: chefe escolhe o editor (lista de usuários) em Efeitos');
  chefe.eval(`assignEditorUser('m1','s2','${USERS.ana.id}')`); await chefe.idle();
  ok(await sqlAdmin("select nome||'/'||user_id from station_editors where id='s2'") === 'Ana/' + USERS.ana.id, 'item 10: atribuição do chefe é gravada (nome + usuário)');
}
if(only.includes('7')){
  admin.eval("selectMovie('m1')");
  ok(admin.html().includes('primeiro-link-escondido'), 'item 7: o primeiro link do filme aparece');
  ok(admin.html().includes('https://segundo'), 'item 7: os demais links continuam aparecendo');
}
if(only.includes('8')){
  ana.eval("selectMovie('m1')");
  const h = ana.html();
  ok(!h.includes('title="Excluir link"') && !h.includes('removeLinkLanguage') && !h.includes('updateMovieLinkUrl'), 'item 8: editor não vê excluir link / remover idioma / editar URL');
  ok(!/<input[^>]*driveInput/.test(h) && h.includes('https://drive/um'), 'item 8: DRIVE aparece só leitura para editor');
  ok(h.includes('primeiro-link-escondido') && /copyText|copyPath/.test(h), 'item 8: editor ainda vê e copia os links');
  ok(/title="Excluir link"/.test(admin.html()) && /<input[^>]*driveInput/.test(admin.html()), 'item 8: admin continua com os controles');
}
if(only.includes('9')){
  ana.eval("selectMovie('m1')");
  ok(!ana.elements.movieTabs.innerHTML.includes('draggable="true"'), 'item 9: fila não é arrastável para editor');
  ok(chefe.elements.movieTabs.innerHTML.includes('draggable="true"'), 'item 9: fila continua arrastável para chefe');
  ana.log.length = 0;
  ana.eval("dropMovie({ preventDefault(){}, dataTransfer:{ getData:()=>'m2' } }, 'm1')"); await ana.idle();
  ok(!ana.log.some(l => l.includes('reorder')), 'item 9: soltar como editor não tenta gravar');
}
if(only.includes('idiomas')){
  chefe.eval("selectMovie('m1'); switchDept('vocal')");
  ok(chefe.html().includes('removeLangRow') && chefe.html().includes('toggleLangPicker'), 'chefe vê adicionar e remover idioma');
  chefe.eval("removeLangRow('m1','e1','r2')"); await chefe.idle();
  ok(await sqlAdmin("select count(*) from station_vocal_rows where id='r2'") === '0', 'chefe remove idioma (gravado no servidor)');
  ok(!ana.html().includes('removeLangRow') && !ana.html().includes('toggleLangPicker'), 'editor continua sem adicionar/remover idioma');
}
if(only.includes('11')){
  let erro = null;
  try { await ana.eval('signOut()'); } catch(e) { erro = e.message; }
  await sleep(50);
  ok(!erro, 'item 11: sair não gera erro', erro);
  ok(ana.elements.content.innerHTML.includes('Nenhum filme') && !ana.html().includes('Filme Um'), 'item 11: dados somem da tela ao sair');
  ok(ana.elements.authOverlay.style.display === 'flex', 'item 11: tela de login volta');
}
console.log(`\n${pass} passaram, ${fail} falharam`); closeAll(); process.exit(fail ? 1 : 0);
