#!/bin/bash
# Recria o banco de teste do zero: stub do Supabase + dados no formato v1 + migrações 2.0.
# Requer um PostgreSQL local em 127.0.0.1:54329 (usuário postgres, sem senha). Ver testes/LEIA-ME.md.
set -e
DIR="$(cd "$(dirname "$0")" && pwd)"
W="$DIR/../supabase/migrations"
P="psql -h 127.0.0.1 -p 54329 -U postgres -v ON_ERROR_STOP=1 -q"
$P -c "drop database if exists estacao_e2e" -c "create database estacao_e2e" 2>/dev/null
P="$P -d estacao_e2e"
$P -f "$DIR/00_supabase_stub.sql" 2>/dev/null
$P -f "$DIR/01_payload_v1.sql"
$P -f "$W/2026110801_estacao_v2_estrutura.sql"
$P -f "$W/2026110802_estacao_v2_migrar_dados.sql" >/dev/null 2>&1
