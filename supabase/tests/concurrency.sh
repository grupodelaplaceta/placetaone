#!/usr/bin/env bash
# Concurrencia: 20 transferencias simultáneas de 10 Pz desde una cuenta con 100 Pz → exactamente 10 deben pasar y el saldo nunca puede ser negativo.
# Uso: PSQL="psql -h host -U user -d db -v ON_ERROR_STOP=0 -qAt" ./concurrency.sh
set -e; PSQL=${PSQL:-psql -qAt}
IDS=$($PSQL -c "
 with b as (select id from plone27_banks where code='0001'), s as (select id from plone27_accounts where name='Tesoreria'),
 a as (select plone27_open_account((select id from b),'personal','Conc-A',null,null)->>'id' id), c as (select plone27_open_account((select id from b),'personal','Conc-B',null,null)->>'id' id)
 select a.id||' '||c.id||' '||(select id from s) from a,c")
read A B S <<<"$IDS"; $PSQL -c "select plone27_transfer('conc-fund-$A','$S','$A',100,'',null)" >/dev/null
seq 1 20 | xargs -P 20 -I{} $PSQL -c "select plone27_transfer('conc-{}-$A','$A','$B',10,'',null)" >/dev/null 2>&1 || true
OK=$($PSQL -c "select count(*) from plone27_transactions where idempotency_key like 'conc-%-$A' and idempotency_key not like 'conc-fund%'")
BAL=$($PSQL -c "select booked from plone27_account_balances where account_id='$A'")
echo "transferencias aceptadas=$OK saldo_origen=$BAL"; [ "$OK" = 10 ] && [ "$BAL" = 0.00 ] && echo "CONCURRENCIA OK" || { echo "FALLO"; exit 1; }
