-- Pruebas de aceptación (ejecutar en staging). Cada bloque falla con excepción si el criterio no se cumple.
do $$ declare b jsonb; bk uuid; sysa jsonb; a jsonb; c jsonb; t1 uuid; t2 uuid; n int; j uuid; g uuid; p uuid; declare_dbg uuid; begin
 b:=plone27_open_bank('Banco Test',null); bk:=(b->>'id')::uuid; assert b->>'code'='0001','código de entidad';
 update plone27_banks set status='review' where id=bk; update plone27_banks set status='active',approved_by=gen_random_uuid() where id=bk;
 sysa:=plone27_open_account(bk,'system','Tesoreria',null,null); a:=plone27_open_account(bk,'personal','Ana',null,null); c:=plone27_open_account(bk,'personal','Bea',null,null);
 assert a->>'iban'='PZ-0001-0002','IBAN secuencial';
 -- ingreso inicial desde cuenta system (puede quedar negativa)
 perform plone27_transfer('dep1',(sysa->>'id')::uuid,(a->>'id')::uuid,100,'dep',null);
 -- idempotencia
 t1:=plone27_transfer_fee('k1',(a->>'id')::uuid,(c->>'id')::uuid,40,'x',null); t2:=plone27_transfer_fee('k1',(a->>'id')::uuid,(c->>'id')::uuid,40,'x',null);
 assert t1=t2,'idempotencia'; select count(*) into n from plone27_transactions where idempotency_key='k1'; assert n=1;
 assert (select booked from plone27_account_balances where account_id=(a->>'id')::uuid)=60,'saldo derivado';
 -- saldo insuficiente
 begin perform plone27_transfer('k2',(a->>'id')::uuid,(c->>'id')::uuid,500,'x',null); assert false,'debió fallar'; exception when others then assert sqlerrm like 'Saldo%',sqlerrm; end;
 -- asiento descuadrado
 begin perform plone27_post('k3','t','x',jsonb_build_array(jsonb_build_object('account',a->>'id','dir','debit','amount',5)),null); assert false; exception when others then assert sqlerrm like 'Asiento%',sqlerrm; end;
 -- ledger inmutable
 begin delete from plone27_ledger_entries; assert false; exception when others then assert sqlerrm like 'Registro contable%',sqlerrm; end;
 -- reverso
 perform plone27_reverse('r1',t1,'error',null); assert (select booked from plone27_account_balances where account_id=(a->>'id')::uuid)=100,'reverso restaura';
 -- IBAN inmutable
 begin update plone27_accounts set iban='PZ-0001-9999' where id=(a->>'id')::uuid; assert false; exception when others then assert sqlerrm like 'IBAN inmutable%',sqlerrm; end;
 -- doble justificación
 insert into plone27_grant_programs(name,kind,budget,funding_account) values('P','subvencion',1000,(sysa->>'id')::uuid) returning id into p;
 insert into plone27_grants(program_id,beneficiary_account,granted) values(p,(a->>'id')::uuid,50) returning id into g;
 t2:=plone27_transfer('g1',(a->>'id')::uuid,(c->>'id')::uuid,30,'gasto',null);
 j:=plone27_justify(g,t2,'F1',30,null);
 begin perform plone27_justify(g,t2,'F2',10,null); assert false; exception when unique_violation then null; end;
 assert (select ref from plone27_grants where id=g) like 'PL27-SUB-%','ref subvención';
 declare_dbg:=plone27_reimburse('re0',j,null); assert declare_dbg is null,'re0 devolvió '||coalesce(declare_dbg::text,'null')||' disp='||plone27_available((sysa->>'id')::uuid);
 assert (select status from plone27_justifications where id=j)='approved','estado='||(select status from plone27_justifications where id=j);
 update plone27_grant_programs set funding_account=(c->>'id')::uuid where id=p;
 perform plone27_reimburse('re1',j,null); assert (select status from plone27_justifications where id=j)='paid'; assert (select reimb_ref from plone27_justifications where id=j) like 'PL27-REE-%','ref reembolso';
 -- tarjeta: diseño con datos de seguridad rechazado
 begin insert into plone27_card_designs(name,tier,elements) values('X','free','{"cvv":1}'); assert false; exception when check_violation then null; end;
 raise notice 'TODAS LAS PRUEBAS OK'; end $$;
do $$ declare bk uuid; s uuid; a uuid; c uuid; jn uuid; bt uuid; r jsonb; ca uuid; begin
 select id into bk from plone27_banks where code='0001'; select id into s from plone27_accounts where name='Tesoreria';
 a:=(plone27_open_account(bk,'personal','Lim',null,null)->>'id')::uuid; c:=(plone27_open_account(bk,'personal','Dest',null,null)->>'id')::uuid; jn:=(plone27_open_account(bk,'junior','Kid',null,null)->>'id')::uuid;
 update plone27_accounts set daily_limit=50 where id=a; perform plone27_transfer('l0',s,a,200,'',null);
 perform plone27_transfer('l1',a,c,40,'',null);
 begin perform plone27_transfer('l2',a,c,20,'',null); assert false; exception when others then assert sqlerrm like 'Límite diario%',sqlerrm; end;
 insert into plone27_juniors values(jn,'2015-01-01',gen_random_uuid(),10); perform plone27_transfer('l3',s,jn,100,'',null);
 begin perform plone27_transfer('l4',jn,c,30,'',null); assert false; exception when others then assert sqlerrm like 'Junior%',sqlerrm; end;
 insert into plone27_batches(kind,from_account) values('payroll',s) returning id into bt; insert into plone27_batch_items(batch_id,to_account,amount) values(bt,c,5),(bt,c,7);
 r:=plone27_run_batch(bt,null); assert (r->>'paid')::int=2,'lote'; r:=plone27_run_batch(bt,null); assert (select count(*) from plone27_transactions where idempotency_key like 'batch:%')=2,'lote idempotente';
 ca:=(plone27_issue_card(a,'physical',null,null,false,null)->>'id')::uuid; perform plone27_card_order_step(ca,'ordered',null); assert (select status from plone27_cards where id=ca)='suspended';
 perform plone27_card_order_step(ca,'produced',null); perform plone27_card_order_step(ca,'shipped',null); perform plone27_card_order_step(ca,'activated',null); assert (select status from plone27_cards where id=ca)='active';
 assert plone27_settle_bank(bk,current_date-1,current_date,null)=plone27_settle_bank(bk,current_date-1,current_date,null),'liquidación idempotente';
 assert plone27_cash_forecast(30,null) is not null; raise notice 'FASE 4 OK'; end $$;
do $$ declare bk uuid; s uuid; pa uuid; col uuid; ru uuid; v1 uuid; v2 uuid; rc uuid; adj uuid; me uuid:=gen_random_uuid(); other uuid:=gen_random_uuid(); n int; begin
 select id into bk from plone27_banks where code='0001'; select id into s from plone27_accounts where name='Tesoreria';
 pa:=(plone27_open_account(bk,'personal','Contrib',null,null)->>'id')::uuid; col:=(plone27_open_account(bk,'system','Recaud',null,null)->>'id')::uuid; perform plone27_transfer('t0',s,pa,500,'',null);
 insert into plone27_tax_rules(code,name,collector_account) values('IGF','Test',col) returning id into ru;
 insert into plone27_tax_rule_versions(rule_id,version,method,rate,valid_from,reason) values(ru,1,'brackets',0,current_date-1,'t') returning id into v1;
 insert into plone27_tax_brackets values(v1,0,100,10),(v1,100,null,20); update plone27_tax_rule_versions set status='published',approver=me where id=v1;
 assert plone27_tax_calc(v1,150)=20,'tramos marginales';
 rc:=plone27_tax_issue('IGF',pa,150,'ev1',null,'recibo',current_date+30,me); assert plone27_tax_issue('IGF',pa,150,'ev1',null,'recibo',current_date+30,me)=rc,'evento idempotente';
 perform plone27_tax_pay_partial('p1',rc,5,me); assert (select status from plone27_tax_receipts where id=rc)='partial';
 begin perform plone27_tax_pay_partial('p2',rc,99,me); assert false; exception when others then assert sqlerrm like 'Importe%',sqlerrm; end;
 perform plone27_tax_pay_partial('p3',rc,15,me); assert (select status from plone27_tax_receipts where id=rc)='paid','pago completo tras parciales';
 insert into plone27_tax_rule_versions(rule_id,version,method,rate,valid_from,reason,retro_mode) values(ru,2,'percent',50,current_date-1,'t','simulation') returning id into v2; update plone27_tax_rule_versions set status='published',approver=me where id=v2;
 adj:=plone27_adjust_simulate(rc,v2,me); update plone27_config set value='1' where key='dual_approval_threshold';
 begin perform plone27_adjust_approve(adj,me); assert false; exception when others then assert sqlerrm like 'Doble%',sqlerrm; end;
 perform plone27_adjust_approve(adj,other); perform plone27_adjust_execute(adj,other);
 assert (select count(*) from plone27_outbox where event='transaction.posted')>5,'outbox'; select count(*) into n from plone27_alerts; assert n=6,'alertas';
 raise notice 'CIERRE OK'; end $$;
