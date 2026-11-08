// Item 3: dados maliciosos gravados no banco não podem virar código na tela.
import { execFileSync } from 'node:child_process';
import { openBrowser, sqlAdmin, closeAll, USERS } from './harness.mjs';

let pass = 0, fail = 0;
function ok(cond, desc, extra = ''){
  if(cond){ pass++; console.log('PASS |', desc); } else { fail++; console.log('**FAIL** |', desc, extra ? '| ' + extra : ''); }
}
execFileSync(new URL('./reset_db.sh', import.meta.url).pathname);

const EVIL = `x'"><img src=x onerror=alert(1)><svg onload=alert(2)>`;
const EVIL_ID = `id'");alert(3);//"`;
const lit = s => '$E$' + s + '$E$';
await sqlAdmin(`
  insert into station_movies(id, position, nome, drive) values (${lit(EVIL_ID)}, 0, ${lit(EVIL)}, ${lit(EVIL)});
  insert into station_movie_links(id, movie_id, position, type, url, languages) values
    ('L0', ${lit(EVIL_ID)}, 0, 'Mono', '', '[]'),
    (${lit(EVIL_ID + 'L')}, ${lit(EVIL_ID)}, 1, ${lit(EVIL)}, ${lit(EVIL)},
     ${lit(JSON.stringify([{ id: EVIL, country: `br" onerror="alert(4)`, name: EVIL }]))});
  insert into station_editors(id, movie_id, dept, position, nome, user_id) values
    (${lit(EVIL_ID + 'E')}, ${lit(EVIL_ID)}, 'vocal', 1, ${lit(EVIL)}, null),
    (${lit(EVIL_ID + 'S')}, ${lit(EVIL_ID)}, 'efeitos', 1, ${lit(EVIL)}, null);
  insert into station_vocal_rows(id, editor_id, idioma, revisor) values
    (${lit(EVIL_ID + 'R')}, ${lit(EVIL_ID + 'E')}, ${lit(EVIL)}, ${lit(EVIL)});
  insert into station_completed_movies(nome, entries) values
    (${lit(EVIL)}, ${lit(JSON.stringify([{ idioma: EVIL, editor: EVIL, revisor: EVIL }]))});
  update station_user_access set editor_name = ${lit(EVIL)} where role = 'editor' and editor_name = 'Bruno';
`);

function decode(s){ return s.replace(/&quot;/g, '"').replace(/&#39;/g, "'").replace(/&lt;/g, '<').replace(/&gt;/g, '>').replace(/&amp;/g, '&'); }
function checkHtml(html, who){
  ok(!html.includes('<img src=x'), `${who}: nenhuma tag <img> injetada`);
  ok(!html.includes('<svg'), `${who}: nenhuma tag <svg> injetada`);
  ok(!/onerror="alert/.test(html), `${who}: nenhum atributo onerror injetado`);
  // Todo atributo on*="..." precisa ser JS válido depois de decodificado pelo navegador.
  const handlers = [...html.matchAll(/\son[a-z]+="([^"]*)"/g)].map(m => decode(m[1]));
  let bad = handlers.filter(h => { try { new Function('event', h); return false; } catch { return true; } });
  ok(bad.length === 0, `${who}: ${handlers.length} handlers continuam JS válido`, bad.slice(0, 2).join(' || '));
  bad = handlers.filter(h => /alert\(/.test(h.replace(/"(?:[^"\\]|\\.)*"/g, '""')));
  ok(bad.length === 0, `${who}: o código malicioso só aparece DENTRO de strings`, bad.slice(0, 2).join(' || '));
}

for(const [who, user] of [['admin', USERS.admin], ['chefe', USERS.chefe], ['editor', USERS.ana]]){
  const b = await openBrowser(who, { user });
  b.eval(`selectMovie(${JSON.stringify(EVIL_ID)})`);
  if(who === 'admin') b.eval(`openLinkLangMenuFor = ${JSON.stringify(EVIL_ID + 'L')}; render();`);
  checkHtml(b.html(), who + '/Vocal');
  b.eval(`switchDept('efeitos')`);
  checkHtml(b.html(), who + '/Efeitos');
  b.eval(`showHistory()`);
  checkHtml(b.html(), who + '/Histórico');
  b.eval(`showProduction()`);
  // pôster adulterado no navegador (o banco já recusa; a tela também não pode aceitar)
  b.eval(`store.movies.get(${JSON.stringify(EVIL_ID)}).poster = 'data:image/jpeg;base64,AAAA" onerror="alert(5)'; rebuildState(); render();`);
  ok(!b.html().includes('onerror="alert(5)') && !b.html().includes('base64,AAAA'), `${who}: pôster adulterado não é exibido`);
  // o argumento decodificado do onclick é exatamente o id original
  if(who === 'admin'){
    const m = b.html().match(/onclick="deleteMovie\((.*?)\)"/);
    ok(m && JSON.parse(decode(m[1])) === EVIL_ID, 'admin: id com aspas chega intacto na função (deleteMovie)');
  }
}

console.log(`\n${pass} passaram, ${fail} falharam`);
closeAll();
process.exit(fail ? 1 : 0);
