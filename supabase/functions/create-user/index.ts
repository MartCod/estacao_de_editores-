// Edge Function "create-user" — versão de referência da Estação 2.0.
//
// O código da função que está publicada hoje no Supabase NÃO está no
// repositório. Na auditoria ela respondeu a um pedido feito só com a chave
// pública (sem login) com "Nome, e-mail e senha são obrigatórios", ou seja,
// validou os campos antes de checar quem estava chamando.
//
// Esta versão garante, ANTES de qualquer outra coisa, que quem chama:
//   1) está logado (token válido), e
//   2) tem role = 'admin' em station_user_access.
// Compare com a função publicada antes de substituí-la:
//   supabase functions deploy create-user
//
// Resposta no formato que o painel espera: { success, error?, details? }.
import { createClient } from 'npm:@supabase/supabase-js@2.45.4';

const ROLES = ['editor', 'chief', 'admin'];
const cors = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
};
const json = (body: unknown, status = 200) =>
  new Response(JSON.stringify(body), { status, headers: { ...cors, 'Content-Type': 'application/json' } });

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: cors });
  if (req.method !== 'POST') return json({ success: false, error: 'Método não permitido.' }, 405);

  const url = Deno.env.get('SUPABASE_URL')!;
  const anonKey = Deno.env.get('SUPABASE_ANON_KEY')!;
  const serviceKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!;

  // 1) quem está chamando?
  const authHeader = req.headers.get('Authorization') ?? '';
  const caller = createClient(url, anonKey, { global: { headers: { Authorization: authHeader } } });
  const { data: { user }, error: userError } = await caller.auth.getUser();
  if (userError || !user) return json({ success: false, error: 'Não autenticado.' }, 401);

  // 2) é administrador?
  const admin = createClient(url, serviceKey, { auth: { persistSession: false } });
  const { data: access } = await admin
    .from('station_user_access').select('role').eq('user_id', user.id).maybeSingle();
  if (access?.role !== 'admin') {
    return json({ success: false, error: 'Somente administradores podem criar usuários.' }, 403);
  }

  // 3) só agora valida os dados
  let body: { name?: string; email?: string; password?: string; role?: string };
  try { body = await req.json(); } catch { return json({ success: false, error: 'Corpo inválido.' }, 400); }
  const name = String(body.name ?? '').trim();
  const email = String(body.email ?? '').trim();
  const password = String(body.password ?? '');
  const role = String(body.role ?? 'editor');
  if (!name || !email || !password) return json({ success: false, error: 'Nome, e-mail e senha são obrigatórios.' }, 400);
  if (password.length < 6) return json({ success: false, error: 'A senha deve ter pelo menos 6 caracteres.' }, 400);
  if (!ROLES.includes(role)) return json({ success: false, error: 'Função inválida.' }, 400);

  const { data: created, error: createError } = await admin.auth.admin.createUser({
    email, password, email_confirm: true, user_metadata: { name },
  });
  if (createError || !created.user) {
    return json({ success: false, error: 'Não foi possível criar o usuário.', details: createError?.message }, 400);
  }

  const { error: accessError } = await admin
    .from('station_user_access')
    .insert({ user_id: created.user.id, role, editor_name: name });
  if (accessError) {
    await admin.auth.admin.deleteUser(created.user.id); // desfaz para não deixar usuário sem perfil
    return json({ success: false, error: 'Usuário não foi criado (falha ao gravar o perfil).', details: accessError.message }, 500);
  }

  return json({ success: true, user_id: created.user.id });
});
