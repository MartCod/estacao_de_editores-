# Testes da Estação 2.0

Rodam o `<script>` do `index.html` no Node (um contexto por "navegador", com DOM mínimo)
contra um PostgreSQL local que imita o Supabase. Cada consulta roda **como o usuário
logado** (papel `authenticated` + `auth.uid()`), então RLS e gatilhos valem de verdade.

Não testa: aparência no navegador real, o Realtime real do Supabase (há um barramento
que imita) e a Edge Function.

## Preparar (uma vez)
```bash
/usr/lib/postgresql/16/bin/initdb -D /tmp/pg-estacao -U postgres --auth=trust -E UTF8
/usr/lib/postgresql/16/bin/pg_ctl -D /tmp/pg-estacao -o "-p 54329 -k '' -c listen_addresses=127.0.0.1" -l /tmp/pg-estacao.log start
```

## Rodar
```bash
cd testes
./reset_db.sh && psql -h 127.0.0.1 -p 54329 -U postgres -d estacao_e2e -tA -f 02_permissoes.sql  # 51 testes de permissão no banco
node test_dados.mjs    # 40: carga, concorrência, permissões, tempo real, RPCs, export/import
node test_xss.mjs      # 49: dados maliciosos não viram código na tela
node test_itens.mjs    # 17: itens 6 a 11 da auditoria
```
