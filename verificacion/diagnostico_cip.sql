-- DIAGNÓSTICO DE SOLO LECTURA: por qué una cuenta de empresa no muestra su CIP en la API.
-- Uso: psql "$DATABASE_URL" -v iban='PZ-0000-0007' -v dip='23749931M' -f verificacion/diagnostico_cip.sql
\echo '1. La cuenta: banco y estado'
select a.id, a.iban, a.bank_id, a.kind, a.status from plone27_accounts a where a.iban = :'iban';

\echo '2. Empresas que contienen la cuenta y su entidad vinculada (entidad_cip)'
select e.id, e.nombre, e.identificador_fiscal, e.bank_id, e.entidad_cip, e.estado
from plone27_empresa_cuentas ec
join plone27_empresas e on e.id = ec.empresa_id
join plone27_accounts a on a.id = ec.account_id
where a.iban = :'iban';

\echo '3. La entidad a la que apunta ese CIP: ¿existe, es del mismo banco, está activa?'
select en.cip, en.bank_id, en.account_id, en.activa
from plone27_entidades en
where en.cip in (
  select e.entidad_cip from plone27_empresa_cuentas ec
  join plone27_empresas e on e.id = ec.empresa_id
  join plone27_accounts a on a.id = ec.account_id
  where a.iban = :'iban');

\echo '4. Lo que devuelve la función que alimenta GET /me/accounts para el titular'
select * from plone27_user_accounts(
  (select p.id from plone27_personas p where p.dip = :'dip'),
  (select a.bank_id from plone27_accounts a where a.iban = :'iban'))
where iban = :'iban';

\echo 'Interpretación:'
\echo '- Si 2 muestra entidad_cip y 4 muestra cip: el problema está en la banca (caché o campo no leído).'
\echo '- Si 2 no muestra entidad_cip: el vínculo no se guardó en esta base de datos (¿otra base, otro entorno?).'
\echo '- Si 3 no devuelve fila o el banco no coincide con el de la cuenta: la entidad no es válida para esta empresa.'
\echo '- Si 2 y 3 están bien pero 4 no devuelve cip: la función de cuentas no está actualizada (revisar 0047).'
