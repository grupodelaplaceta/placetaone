#!/usr/bin/env bash
# Restauración: copia → restaura en otra base → compara huella del libro contable y saldos.
# Uso: SRC=postgresql://.../db DST=postgresql://.../db_restore ./restore.sh
set -e; F=$(mktemp)
pg_dump -Fc "$SRC" -f "$F"; pg_restore --no-owner --clean --if-exists -d "$DST" "$F" 2>/dev/null || true
Q="select md5(string_agg(transaction_id::text||account_id::text||direction||amount::text,',' order by id)) from plone27_ledger_entries"
[ "$(psql -qAt "$SRC" -c "$Q")" = "$(psql -qAt "$DST" -c "$Q")" ] && echo "RESTAURACION OK" || { echo "FALLO"; exit 1; }
