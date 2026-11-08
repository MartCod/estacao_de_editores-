# Estação de Editores 2.0 — como colocar no ar

A 2.0 muda **onde os dados ficam** (de um registro JSON único para tabelas `station_*`).
Por isso a ordem dos passos importa. Nada aqui apaga a tabela antiga
`editor_panel_shared_data`: ela continua sendo o backup da versão 1.

## Antes de começar
1. Na versão 1 (no ar), entre como admin e clique em **Exportar dados** (backup extra).
2. Confira a Edge Function `create-user` publicada no Supabase (Dashboard → Edge Functions).
   Ela precisa recusar quem não é admin. Se não recusar, publique a versão de
   `supabase/functions/create-user/index.ts`. Ela grava `user_id`, `role` e `editor_name`
   em `station_user_access`. Se a sua tabela tiver outras colunas obrigatórias, ajuste antes.

## Passos (de preferência num horário sem ninguém editando)
| # | Onde | O quê |
|---|------|-------|
| 1 | Supabase → SQL Editor | rodar `supabase/migrations/2026110801_estacao_v2_estrutura.sql` (não afeta a v1) |
| 2 | Supabase → SQL Editor | rodar `2026110802_estacao_v2_migrar_dados.sql` e conferir as contagens |
| 3 | Servidor | publicar o `index.html` da branch `estacao-2.0` (merge ou checkout em `/var/www/estacao_de_editores-`) |
| 4 | Navegador | entrar como admin, chefe e editor e conferir (lista abaixo) |
| 5 | Supabase → SQL Editor | rodar `2026110803_estacao_v2_bloquear_tabela_antiga.sql` (abas antigas param de gravar no registro velho) |
| 6 | Servidor (sudo) | aplicar `deploy/nginx-painel.conf`, depois `sudo nginx -t && sudo systemctl reload nginx` |

O passo 2 copia o estado do momento. O que alguém fizer na v1 entre o passo 2 e o 3 não vai para a 2.0.
Se isso acontecer, rode o passo 2 de novo com `v_forcar := true`.

**Realtime:** o passo 1 adiciona as tabelas à publicação `supabase_realtime`. Se aparecer o aviso
"Publicação supabase_realtime não encontrada", ative o Realtime para as tabelas `station_*` no
Dashboard (Database → Replication). Sem Realtime o painel funciona, mas só vê as mudanças dos
outros a cada 30 s.

## Conferir no navegador (passo 4)
- Os filmes, editores, idiomas, links e histórico batem com a v1. O **primeiro link** de cada filme
  agora aparece (antes ficava escondido).
- Abra o painel em dois navegadores. Uma mudança feita em um aparece no outro em segundos.
- Como editor: dá para mudar datas e status das **próprias** tarefas (Vocal, Efeitos e Música), e nada além disso.
- Como chefe: dá para mudar urgência, revisor, status e editor responsável, e adicionar ou remover idiomas, mas não datas.
- O indicador mostra "Alterações salvas". Se mostrar "Erro ao salvar", abra o console (F12) e veja a mensagem.
- Em Efeitos/Música, editores que eram só um nome digitado aparecem como "Nome (sem usuário)" até
  o chefe escolher o usuário na lista. Enquanto isso, o editor não consegue mexer na própria tarefa.

## Voltar para a versão 1
Republique o `index.html` antigo e rode `supabase/reverter_estacao_v2.sql`. Esse script apaga as tabelas
`station_*`. Se quiser guardar o que foi feito na 2.0, use antes **Exportar dados** na 2.0 e
**Importar dados** na v1 (o formato do arquivo é o mesmo).

## Observações
- **Certificado HTTPS:** é autoassinado. A correção é ter um domínio apontando para o servidor e usar
  Let's Encrypt (`certbot --nginx`). Isso não dá para resolver dentro do código.
- **Atualizar o supabase-js:** troque a versão no `<script>` e recalcule o hash:
  `curl -s URL | openssl dgst -sha384 -binary | openssl base64 -A`
- **Pôsteres:** continuam como imagem JPEG embutida, agora numa coluna própria (máx. 2 MB pelo painel).
  Mudar o nome do filme não reenvia mais o pôster. Se no futuro ficarem pesados, o próximo passo
  é o Supabase Storage.
- **Dados locais antigos:** a 2.0 não usa mais `estacao_editores_v3` do localStorage (a v1 guardava
  uma cópia de tudo no navegador). A cópia antiga fica parada lá e pode ser apagada.
- **Testes automatizados:** ver `testes/LEIA-ME.md`.
