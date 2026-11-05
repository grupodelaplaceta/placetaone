-- PRUEBAS DE BASE DE DATOS (ejecutar en una base de PRUEBAS, nunca en producción)
-- Uso: psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -v cuenta_a='PZ-…' -v cuenta_b='PZ-…' -f verificacion/pruebas_db.sql
-- Las cuentas deben existir (dos cuentas de la misma o de distinta entidad). Todo se hace dentro de una transacción
-- que termina en ROLLBACK: no deja datos. Si alguna prueba falla, aparece FALLO y se detiene.
\set ON_ERROR_STOP on
BEGIN;
SELECT (SELECT id FROM plone27_accounts WHERE iban = :'cuenta_a') AS a,
       (SELECT id FROM plone27_accounts WHERE iban = :'cuenta_b') AS b \gset
CREATE TEMP TABLE cfg AS SELECT :'a'::uuid AS a, :'b'::uuid AS b;
UPDATE plone27_accounts SET allow_negative = true WHERE id IN (:'a'::uuid, :'b'::uuid);

-- 1. Transferencia idempotente: misma clave, mismo movimiento
DO $t$ declare c record; t1 uuid; t2 uuid; antes numeric; despues numeric; begin
  select * into c from cfg;
  antes := plone27_available(c.b);
  t1 := plone27_transfer('test-idem-1', c.a, c.b, 10, 'prueba', null);
  t2 := plone27_transfer('test-idem-1', c.a, c.b, 10, 'prueba', null);
  if t1 is distinct from t2 then raise exception 'FALLO 1: la repetición devolvió otra transacción'; end if;
  despues := plone27_available(c.b);
  if despues - antes <> 10 then raise exception 'FALLO 1: el destino recibió % en lugar de 10', despues-antes; end if;
  raise notice 'OK 1: transferencia idempotente';
end $t$;

-- 2. Misma clave con importe distinto: debe fallar
DO $t$ declare c record; begin
  select * into c from cfg;
  begin
    perform plone27_transfer('test-idem-1', c.a, c.b, 11, 'prueba', null);
    raise exception 'FALLO 2: se aceptó una clave reutilizada con otro importe';
  exception when others then
    if sqlerrm like 'FALLO 2%' then raise; end if;
    raise notice 'OK 2: clave reutilizada con datos distintos rechazada';
  end;
end $t$;

-- 3. Cobro de deuda repetido: la deuda NO debe contar el pago dos veces
DO $t$ declare c record; per uuid; deb uuid; p1 uuid; p2 uuid; pagado numeric; begin
  select * into c from cfg;
  per := plone27_persona('TESTDIP01');
  insert into plone27_debts(account_id,principal,authorized_by,reason,creditor_account,ref,due_date)
    values(c.a,100,per,'prueba de idempotencia',c.b,'TEST-IDEM-DEUDA',current_date) returning id into deb;
  p1 := plone27_debt_pay('test-deuda-1', deb, 30, null);
  p2 := plone27_debt_pay('test-deuda-1', deb, 30, null);
  select paid into pagado from plone27_debts where id = deb;
  if p1 is distinct from p2 then raise exception 'FALLO 3: la repetición devolvió otra transacción'; end if;
  if pagado <> 30 then raise exception 'FALLO 3: la deuda cuenta % pagado en lugar de 30 (pago contado dos veces)', pagado; end if;
  raise notice 'OK 3: cobro de deuda idempotente';
end $t$;

-- 4. Misma clave de cobro con importe distinto: debe fallar y no tocar la deuda
DO $t$ declare c record; deb uuid; pagado numeric; begin
  select * into c from cfg;
  select id into deb from plone27_debts where ref = 'TEST-IDEM-DEUDA';
  begin
    perform plone27_debt_pay('test-deuda-1', deb, 20, null);
    raise exception 'FALLO 4: se aceptó una clave de cobro reutilizada con otro importe';
  exception when others then
    if sqlerrm like 'FALLO 4%' then raise; end if;
  end;
  select paid into pagado from plone27_debts where id = deb;
  if pagado <> 30 then raise exception 'FALLO 4: la deuda cambió tras el intento rechazado (%)', pagado; end if;
  raise notice 'OK 4: clave de cobro reutilizada rechazada sin efectos';
end $t$;

-- 5. Reclamación y devolución: la deuda baja y la reclamación queda devuelta
DO $t$ declare c record; deb uuid; per uuid; x uuid; r jsonb; pagado numeric; begin
  select * into c from cfg;
  select id into deb from plone27_debts where ref = 'TEST-IDEM-DEUDA';
  per := plone27_persona('TESTDIP01');
  insert into plone27_disputas(debt_id,account_id,monto_reclamado,motivo,abierta_por,plazo_resolucion)
    values(deb,c.a,20,'prueba de devolución',per,current_date+30) returning id into x;
  update plone27_debts set disputed = true where id = deb;
  r := plone27_disputa_resolver(x,'devolucion',null,gen_random_uuid());
  select paid into pagado from plone27_debts where id = deb;
  if r->>'estado' <> 'devuelta' then raise exception 'FALLO 5: estado inesperado %', r; end if;
  if pagado <> 10 then raise exception 'FALLO 5: tras devolver 20 la deuda debe tener 10 pagado, tiene %', pagado; end if;
  raise notice 'OK 5: devolución por reclamación';
end $t$;

-- 6. Parámetros: un valor fuera de rango debe rechazarse
DO $t$ begin
  begin
    perform plone27_parametro_set('disputa.plazo_apertura_dias', 9999, gen_random_uuid());
    raise exception 'FALLO 6: se aceptó un plazo fuera de rango';
  exception when others then
    if sqlerrm like 'FALLO 6%' then raise; end if;
    raise notice 'OK 6: parámetro fuera de rango rechazado';
  end;
end $t$;

ROLLBACK;
\echo 'Pruebas terminadas. Si no aparece FALLO, todas las comprobaciones han pasado (la transacción se ha revertido).'
