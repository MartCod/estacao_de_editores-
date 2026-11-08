// Harness de teste da Estação de Editores 2.0.
// Roda o <script> do index.html em contextos isolados do Node (um por "navegador"),
// com um DOM mínimo e um cliente Supabase falso que executa as consultas no
// PostgreSQL de teste COMO o usuário logado (RLS e gatilhos valem de verdade).
import fs from 'node:fs';
import vm from 'node:vm';
import { execFile } from 'node:child_process';

export const sleep = ms => new Promise(r => setTimeout(r, ms));
const DB = ['-h', '127.0.0.1', '-p', '54329', '-U', 'postgres', '-d', 'estacao_e2e', '-tA', '-q'];

export const USERS = {
  admin: { id: 'aaaaaaaa-0000-0000-0000-000000000001', email: 'admin@x' },
  chefe: { id: 'cccccccc-0000-0000-0000-000000000001', email: 'chefe@x' },
  ana:   { id: 'eeeeeeee-0000-0000-0000-000000000001', email: 'ana@x' },
  bruno: { id: 'eeeeeeee-0000-0000-0000-000000000002', email: 'bruno@x' },
};

function psql(sql){
  return new Promise(resolve => {
    const p = execFile('psql', [...DB, '-v', 'ON_ERROR_STOP=1'], { maxBuffer: 64 << 20 }, (err, stdout, stderr) => {
      resolve({ err, stdout, stderr });
    });
    p.stdin.end(sql);
  });
}

export async function sqlAdmin(sql){
  const { err, stdout, stderr } = await psql(sql);
  if(err) throw new Error(stderr);
  return stdout.trim();
}

function lit(v){
  if(v === null || v === undefined) return 'null';
  if(typeof v === 'number') return String(v);
  if(typeof v === 'boolean') return v ? 'true' : 'false';
  const s = String(v);
  if(s.includes('$Q$')) throw new Error('valor de teste inválido');
  return '$Q$' + s + '$Q$';
}
function jlit(o){
  const s = JSON.stringify(o);
  if(s.includes('$J$')) throw new Error('json de teste inválido');
  return '$J$' + s + '$J$';
}

// Barramento que imita o Realtime entre os "navegadores" abertos.
const bus = new Set();
function broadcast(from, table, eventType, rows){
  for(const sub of bus){
    if(sub.client === from || sub.table !== table) continue;
    for(const row of rows){
      sub.cb(eventType === 'DELETE' ? { eventType, old: { id: row.id } } : { eventType, new: row });
    }
  }
}

async function runAs(user, statement){
  const sql = `\\set VERBOSITY verbose
begin;
set local role authenticated;
select set_config('request.jwt.claims', ${lit(JSON.stringify({ sub: user ? user.id : '' }))}, true) is null;
${statement};
commit;
`;
  const { err, stdout, stderr } = await psql(sql);
  if(err){
    const m = stderr.match(/ERROR:\s+([0-9A-Z]{5}):\s+(.*)/);
    return { error: { code: m ? m[1] : 'XX000', message: m ? m[2] : stderr } };
  }
  // 1ª linha = resultado do set_config; o resto é o JSON (pode ter várias linhas)
  const lines = stdout.replace(/\n$/, '').split('\n');
  return { data: JSON.parse(lines.slice(1).join('\n')) };
}

class Query {
  constructor(client, table){
    Object.assign(this, { client, table, op: 'select', cols: '*', filters: [], orderBy: null, rng: null, mode: 'many', returning: false });
  }
  select(cols = '*'){ if(this.op === 'select') this.cols = cols; else { this.returning = true; this.retCols = cols; } return this; }
  update(p){ this.op = 'update'; this.payload = p; return this; }
  insert(p){ this.op = 'insert'; this.payload = p; return this; }
  upsert(p){ this.op = 'upsert'; this.payload = p; return this; }
  delete(){ this.op = 'delete'; return this; }
  eq(c, v){ this.filters.push(`${c} = ${lit(v)}`); return this; }
  in(c, a){ this.filters.push(`${c} in (${a.map(lit).join(',')})`); return this; }
  order(c, o){ this.orderBy = `${c} ${o && o.ascending === false ? 'desc' : 'asc'}`; return this; }
  range(a, b){ this.rng = [a, b]; return this; }
  maybeSingle(){ this.mode = 'maybe'; return this; }
  single(){ this.mode = 'single'; return this; }
  then(res, rej){ return this.exec().then(res, rej); }
  async exec(){
    const t = `public.${this.table}`;
    const where = this.filters.length ? ' where ' + this.filters.join(' and ') : '';
    let stmt;
    if(this.op === 'select'){
      let inner = `select ${this.cols} from ${t}${where}`;
      if(this.orderBy) inner += ` order by ${this.orderBy}`;
      if(this.rng) inner += ` limit ${this.rng[1] - this.rng[0] + 1} offset ${this.rng[0]}`;
      stmt = `select coalesce(json_agg(x), '[]') from (${inner}) x`;
    }else if(this.op === 'update'){
      const cols = Object.keys(this.payload).join(', ');
      stmt = `with x as (update ${t} set (${cols}) = (select ${cols} from json_populate_record(null::${t}, ${jlit(this.payload)}))${where} returning *) select coalesce(json_agg(x), '[]') from x`;
    }else if(this.op === 'insert'){
      const cols = Object.keys(this.payload).join(', ');
      stmt = `with x as (insert into ${t} (${cols}) select ${cols} from json_populate_record(null::${t}, ${jlit(this.payload)}) returning *) select coalesce(json_agg(x), '[]') from x`;
    }else if(this.op === 'delete'){
      stmt = `with x as (delete from ${t}${where} returning *) select coalesce(json_agg(x), '[]') from x`;
    }else{
      throw new Error('operação não suportada no harness: ' + this.op);
    }
    this.client.log.push(`${this.op} ${this.table}${where}`);
    const r = await runAs(this.client.user, stmt);
    if(r.error) return { data: null, error: r.error };
    let rows = r.data;
    if(this.op !== 'select' && rows.length){
      broadcast(this.client, this.table, { update: 'UPDATE', insert: 'INSERT', delete: 'DELETE' }[this.op], rows);
    }
    if(this.op !== 'select' && !this.returning) rows = null;
    if(this.mode === 'single'){
      if(!rows || rows.length !== 1) return { data: null, error: { code: 'PGRST116', message: 'JSON object requested, multiple (or no) rows returned' } };
      return { data: rows[0], error: null };
    }
    if(this.mode === 'maybe'){
      if(rows && rows.length > 1) return { data: null, error: { code: 'PGRST116', message: 'multiple rows' } };
      return { data: rows && rows.length ? rows[0] : null, error: null };
    }
    return { data: rows, error: null };
  }
}

const RPC = {
  station_create_movie: () => `public.station_create_movie()`,
  station_complete_movie: a => `public.station_complete_movie(${lit(a.p_movie_id)})`,
  station_reorder_movies: a => `public.station_reorder_movies(array[${a.p_ids.map(lit).join(',')}]::text[])`,
  station_import: a => `public.station_import(${jlit(a.p)}::jsonb)`,
};

function makeSupabase(client){
  return {
    from: table => new Query(client, table),
    async rpc(name, args){
      client.log.push('rpc ' + name);
      const r = await runAs(client.user, `select to_json(${RPC[name](args || {})})`);
      return r.error ? { data: null, error: r.error } : { data: r.data, error: null };
    },
    channel(){
      const ch = { subs: [], on(type, filter, cb){ const s = { client, table: filter.table, cb }; this.subs.push(s); bus.add(s); return this; },
        subscribe(cb){ client.realtimeEnabled ? cb('SUBSCRIBED') : cb('CHANNEL_ERROR'); return this; } };
      return ch;
    },
    removeChannel(ch){ ch.subs.forEach(s => bus.delete(s)); },
    functions: { async invoke(){ return { data: { success: true }, error: null }; } },
    auth: {
      async getSession(){ return { data: { session: client.user ? { user: client.user } : null } }; },
      async signInWithPassword({ email, password }){
        const u = Object.values(USERS).find(x => x.email === email);
        if(!u || password !== 'senha123') return { data: {}, error: { message: 'Invalid login credentials' } };
        client.user = u;
        return { data: { user: u }, error: null };
      },
      async signOut(){ client.user = null; client.authCb && client.authCb('SIGNED_OUT', null); return { error: null }; },
      onAuthStateChange(cb){ client.authCb = cb; return { data: { subscription: { unsubscribe(){} } } }; },
    },
  };
}

function classList(){
  const set = new Set();
  return {
    add(...t){ t.forEach(x => { if(x === '') { const e = new Error("Failed to execute 'add' on 'DOMTokenList': The token provided must not be empty."); e.name = 'SyntaxError'; throw e; } set.add(x); }); },
    remove(...t){ t.forEach(x => set.delete(x)); },
    toggle(t, f){ (f === undefined ? !set.has(t) : f) ? set.add(t) : set.delete(t); },
    contains(t){ return set.has(t); },
    toString(){ return [...set].join(' '); },
  };
}
function el(id){
  return { id, innerHTML: '', textContent: '', value: '', style: {}, dataset: {}, classList: classList(),
    focus(){}, click(){}, remove(){}, appendChild(){}, contains(){ return false; }, closest(){ return null; },
    matches(){ return false; }, querySelector(){ return null; }, querySelectorAll(){ return []; }, setAttribute(){} };
}

const SCRIPT = (() => {
  const html = fs.readFileSync(process.env.INDEX || new URL('../index.html', import.meta.url).pathname, 'utf8');
  const all = [...html.matchAll(/<script>([\s\S]*?)<\/script>/g)];
  return all[all.length - 1][1];
})();

export async function openBrowser(name, { user = null, realtime = true, localStorageData = {} } = {}){
  const client = { name, user, log: [], alerts: [], errors: [], realtimeEnabled: realtime, authCb: null };
  const ids = ['authOverlay', 'userSession', 'saveStatus', 'logoutBtn', 'themeBtnDark', 'themeBtnLight', 'importBtn',
    'exportBtn', 'newUserBtn', 'importFile', 'movieTabs', 'content', 'deptTabs', 'authEmail', 'authPassword', 'authError'];
  const elements = Object.fromEntries(ids.map(id => [id, el(id)]));
  const docListeners = {}; const winListeners = {};
  const body = el('body');
  const document = {
    body, hidden: false, activeElement: body,
    getElementById: id => elements[id] || null,
    addEventListener: (t, f) => { (docListeners[t] ||= []).push(f); },
    removeEventListener(){},
    createElement: () => el('dyn'),
    querySelectorAll: () => [],
  };
  const ls = new Map(Object.entries(localStorageData));
  const sandbox = {
    console: { log: (...a) => client.log.push(a.join(' ')), error: (...a) => client.errors.push(a.map(x => x && x.message ? x.message : String(x)).join(' ')), warn(){} },
    document, setTimeout, clearTimeout, setInterval, clearInterval, Promise, JSON, Date, Math, Map, Set, Object, Array, String, Number, Error, RegExp, Blob: class {},
    URL: { createObjectURL: () => 'blob:x', revokeObjectURL(){} },
    localStorage: { getItem: k => ls.has(k) ? ls.get(k) : null, setItem: (k, v) => ls.set(k, String(v)), removeItem: k => ls.delete(k) },
    alert: m => client.alerts.push(m),
    confirm: () => client.confirmAnswer !== false,
    navigator: { clipboard: { writeText: async () => {} } },
    addEventListener: (t, f) => { (winListeners[t] ||= []).push(f); },
  };
  sandbox.window = sandbox;
  sandbox.supabase = { createClient: () => makeSupabase(client) };
  const ctx = vm.createContext(sandbox);
  vm.runInContext(SCRIPT, ctx, { filename: 'index.html' });
  Object.assign(client, {
    ctx, elements, ls, document, docListeners, winListeners,
    eval: code => vm.runInContext(code, ctx),
    html: () => elements.movieTabs.innerHTML + elements.content.innerHTML + elements.deptTabs.innerHTML,
    status: () => elements.saveStatus.textContent,
    async idle(){ // espera a fila de gravações esvaziar
      for(let i = 0; i < 400; i++){
        await sleep(25);
        if(vm.runInContext('!hasUnsavedChanges()', ctx)) { await vm.runInContext('writeChain', ctx); await sleep(10); if(vm.runInContext('!hasUnsavedChanges()', ctx)) return; }
      }
      throw new Error(name + ': fila de gravação não esvaziou');
    },
  });
  await sleep(50);
  for(let i = 0; i < 100 && user && elements.authOverlay.style.display !== 'none'; i++) await sleep(25);
  return client;
}

export function closeAll(){ bus.clear(); }
