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
 adj:=plone27_adjust_simulate(rc,v2,me); update plone27_settings set value='1' where key='dual_approval_threshold';
 begin perform plone27_adjust_approve(adj,me); assert false; exception when others then assert sqlerrm like 'Doble%',sqlerrm; end;
 perform plone27_adjust_approve(adj,other); perform plone27_adjust_execute(adj,other); update plone27_settings set value='1000' where key='dual_approval_threshold';
 assert (select count(*) from plone27_outbox where event='transaction.posted')>5,'outbox'; select count(*) into n from plone27_alerts; assert n=7,'alertas';
 raise notice 'CIERRE OK'; end $$;
do $$ declare bk uuid; s uuid; col uuid; pa uuid; ru uuid; v1 uuid; v2 uuid; rc uuid; adj uuid; ch uuid; me uuid:=gen_random_uuid(); ot uuid:=gen_random_uuid(); begin
 select id into bk from plone27_banks where code='0001'; select id into s from plone27_accounts where name='Tesoreria'; select id into col from plone27_accounts where name='Recaud';
 begin perform plone27_setting_propose('default_receipt_due_days','9999',null,'x',me); assert false; exception when others then assert sqlerrm like 'Fuera de los límites%',sqlerrm; end;  -- límite central
 begin perform plone27_setting_propose('dual_approval_threshold','10',bk,'x',me); assert false; exception when others then assert sqlerrm like 'Este ajuste solo es central%',sqlerrm; end;
 perform plone27_setting_propose('default_receipt_due_days','15',bk,'banco corto',me); assert plone27_setting('default_receipt_due_days',bk)='15' and plone27_setting('default_receipt_due_days')='30','override por entidad';
 ch:=plone27_setting_propose('dual_approval_threshold','500',null,'más estricto',me); assert plone27_setting('dual_approval_threshold')='1000','sensible queda pendiente';
 begin perform plone27_setting_approve(ch,true,me); assert false; exception when others then assert sqlerrm like 'El proponente%',sqlerrm; end;
 perform plone27_setting_approve(ch,true,ot); assert plone27_setting('dual_approval_threshold')='500','aprobado y aplicado';
 assert plone27_apply_late_penalties(me)=0,'recargo desactivado por defecto';
 pa:=(plone27_open_account(bk,'personal','Contrib2',null,null)->>'id')::uuid;
 insert into plone27_tax_rules(code,name,collector_account) values('IRM','t',col) returning id into ru;
 insert into plone27_tax_rule_versions(rule_id,version,method,rate,valid_from,reason) values(ru,1,'percent',10,current_date-1,'t') returning id into v1; update plone27_tax_rule_versions set status='published',approver=me where id=v1;
 insert into plone27_tax_rule_versions(rule_id,version,method,rate,valid_from,reason,retro_mode) values(ru,2,'percent',5,current_date-1,'t','simulation') returning id into v2; update plone27_tax_rule_versions set status='published',approver=me where id=v2;
 rc:=(select id from plone27_tax_receipts where false); insert into plone27_tax_receipts(rule_version_id,account_id,base,amount,due_date) values(v1,pa,100,10,current_date+5) returning id into rc;
 adj:=plone27_adjust_simulate(rc,v2,me); perform plone27_adjust_approve(adj,me);
 begin perform plone27_adjust_execute(adj,me); assert false; exception when others then assert sqlerrm like 'Política%',sqlerrm; end;
 perform plone27_setting_propose('unpaid_negative_adjustment_policy','"credit_note"',null,'permitir nota de crédito',me); ch:=(select id from plone27_setting_changes where key='unpaid_negative_adjustment_policy' and status='pending');
 perform plone27_setting_approve(ch,true,ot); perform plone27_adjust_execute(adj,me); assert (select amount from plone27_tax_receipts where id=rc)=5,'nota de crédito aplicada';
 raise notice 'CONFIG OK'; end $$;
do $$ declare bk uuid; s uuid; pr uuid; a jsonb; n int; begin
 select id into bk from plone27_banks where code='0001'; select id into s from plone27_accounts where name='Tesoreria';
 insert into plone27_products(code,bank_id,kind,name,daily_limit,monthly_fee,fee_account) values('CTA-BASE',bk,'account_personal','Cuenta Base',100,2,s) returning id into pr;
 begin perform plone27_open_account_p(pr,'X',null,null); assert false; exception when others then assert sqlerrm like 'Producto no disponible%',sqlerrm; end;
 begin update plone27_products set status='active' where id=pr; assert false; exception when others then assert sqlerrm like 'Activar un producto%',sqlerrm; end;
 update plone27_products set status='active',approved_by=gen_random_uuid() where id=pr;
 a:=plone27_open_account_p(pr,'Cliente P',null,null); assert (select daily_limit from plone27_accounts where id=(a->>'id')::uuid)=100 and (select product_id from plone27_accounts where id=(a->>'id')::uuid)=pr,'cuenta hereda producto';
 perform plone27_transfer('fund-p',s,(a->>'id')::uuid,50,'',null); n:=plone27_charge_product_fees(null); assert n>=1; perform plone27_charge_product_fees(null);
 assert (select count(*) from plone27_transactions where idempotency_key like 'pfee:'||(a->>'id')||'%')=1,'cuota mensual idempotente';
 raise notice 'PRODUCTOS OK'; end $$;
do $$ declare bk uuid; s uuid; a uuid; b uuid; c uuid; u uuid:=gen_random_uuid(); r uuid; t uuid; pr uuid; ru uuid; v uuid; rc uuid; tp uuid; begin
 select id into bk from plone27_banks where code='0001'; select id into s from plone27_accounts where name='Tesoreria';
 a:=(plone27_open_account(bk,'personal','M-A',null,null)->>'id')::uuid; b:=(plone27_open_account(bk,'personal','M-B',null,null)->>'id')::uuid; perform plone27_transfer('m0',s,a,100,'',null);
 perform plone27_transfer('mk',a,b,10,'',null);
 begin perform plone27_transfer('mk',a,b,99,'',null); assert false; exception when others then assert sqlerrm like 'Idempotency-Key reutilizada%',sqlerrm; end;
 begin perform plone27_transfer_user('mu',u,a,b,5,'',null); assert false; exception when others then assert sqlerrm like 'El usuario no está autorizado%',sqlerrm; end;
 insert into plone27_account_members values(a,u,'authorized'); perform plone27_transfer_user('mu',u,a,b,5,'',null);
 r:=plone27_reserve(a,80,'t',null); begin perform plone27_transfer('mr',a,b,20,'',null); assert false; exception when others then assert sqlerrm like 'Saldo%',sqlerrm; end;
 perform plone27_release(r,null); perform plone27_transfer('mr',a,b,20,'',null);
 t:=(select id from plone27_transactions where idempotency_key='mk'); perform plone27_reverse('mrev',t,'x',null);
 begin perform plone27_reverse('mrev2',(select id from plone27_transactions where idempotency_key='mrev'),'x',null); assert false; exception when others then assert sqlerrm like 'No se puede revertir%',sqlerrm; end;
 begin delete from plone27_audit_log; assert false; exception when others then assert sqlerrm like 'Registro contable%',sqlerrm; end;
 insert into plone27_products(code,bank_id,kind,name,credit_limit,interest_rate,fee_account,status,approved_by) values('CRD',bk,'internal_credit','Crédito',100,12,s,'active',gen_random_uuid()) returning id into pr;
 c:=(plone27_open_account_p(pr,'Cred',null,null)->>'id')::uuid; perform plone27_transfer('c1',c,b,60,'',null);
 assert (select booked from plone27_account_balances where account_id=c)=-60,'descubierto';
 begin perform plone27_transfer('c2',c,b,50,'',null); assert false; exception when others then assert sqlerrm like 'Límite de crédito%',sqlerrm; end;
 assert plone27_accrue_interest(null)=1; perform plone27_accrue_interest(null); assert (select booked from plone27_account_balances where account_id=c)=-60.60,'interés mensual una sola vez';
 insert into plone27_tax_rules(code,name,collector_account) values('IVAT','t',s) returning id into ru;
 insert into plone27_tax_rule_versions(rule_id,version,method,rate,valid_from,reason,status,approver) values(ru,1,'fixed',10,current_date-1,'t','published',u) returning id into v;
 insert into plone27_tax_receipts(rule_version_id,account_id,base,amount,due_date) values(v,a,0,10,current_date+5) returning id into rc;
 tp:=plone27_tax_pay('tp1',rc,null); assert (select status from plone27_tax_receipts where id=rc)='paid' and (select paid_amount from plone27_tax_receipts where id=rc)=10;
 perform plone27_reverse('trev',tp,'x',null); assert (select status from plone27_tax_receipts where id=rc)='issued','reverso reabre el recibo';
 raise notice 'MOTOR OK'; end $$;
do $$ declare bk uuid; s uuid; c1 uuid; a uuid; pg uuid; pd uuid; ru uuid; v uuid; rc uuid; d uuid; ap uuid:=gen_random_uuid(); me uuid:=gen_random_uuid(); ot uuid:=gen_random_uuid(); dbt uuid; pol jsonb; begin
 select id into bk from plone27_banks where code='0001'; select id into s from plone27_accounts where name='Tesoreria';
 insert into plone27_customers(dip,full_name,bank_id) values('DIP-0001','Ana Prueba',bk) returning id into c1;
 a:=(plone27_open_account(bk,'personal','Cli-A',null,null)->>'id')::uuid; update plone27_accounts set customer_id=c1 where id=a;
 begin insert into plone27_policies(kind,name,scope,params) values('penalty','x','global','{"type":"percent","value":50}'); assert false; exception when others then assert sqlerrm like 'Supera el tope central%',sqlerrm; end;
 begin insert into plone27_policies(kind,name,scope,params,status) values('penalty','x','global','{"type":"percent","value":5}','published'); assert false; exception when others then assert sqlerrm like 'Publicar exige%',sqlerrm; end;
 insert into plone27_policies(kind,name,scope,params,status,approved_by) values('penalty','Global','global','{"type":"percent","value":5,"grace_days":0}','published',ap);
 assert (plone27_policy_resolve('penalty',a)->>'value')::numeric=5,'aplica la global';
 insert into plone27_policies(kind,name,scope,dip,params,status,approved_by) values('penalty','Solo DIP-0001','dip','DIP-0001','{"type":"percent","value":10,"grace_days":0}','published',ap);
 assert (plone27_policy_resolve('penalty',a)->>'value')::numeric=10,'la norma por DIP gana';
 insert into plone27_policies(kind,name,scope,dip,params,status,approved_by) values('penalty','Duplicada','dip','DIP-0001','{"type":"fixed","value":3}','published',ap);
 pol:=plone27_policy_resolve('penalty',a); assert pol is null,'empate: no se aplica ninguna'; assert exists(select 1 from plone27_incidents where kind='policy_conflict'),'empate = incidencia';
 update plone27_policies set status='retired' where name='Duplicada';
 update plone27_settings set value='true' where key='late_penalty_enabled';
 insert into plone27_tax_rules(code,name,collector_account) values('MORA','t',s) returning id into ru;
 insert into plone27_tax_rule_versions(rule_id,version,method,rate,valid_from,reason,status,approver) values(ru,1,'fixed',100,current_date-30,'t','published',ap) returning id into v;
 insert into plone27_tax_receipts(rule_version_id,account_id,base,amount,due_date) values(v,a,0,100,current_date-5) returning id into rc;
 assert plone27_apply_late_penalties(null)>=1,'recargo creado'; select id into dbt from plone27_debts where origin='penalty:'||rc; assert (select principal from plone27_debts where id=dbt)=10,'10% por norma DIP';
 assert plone27_apply_late_penalties(null)=0,'una sola vez por recibo';
 insert into plone27_tax_receipts(rule_version_id,account_id,base,amount,due_date) values(v,a,0,100,current_date-5) returning id into rc;
 d:=plone27_dispute_open('receipt',rc,'Importe erróneo',me); assert (select disputed from plone27_tax_receipts where id=rc);
 assert plone27_apply_late_penalties(null)=0,'recibo en disputa no se penaliza';
 begin perform plone27_dispute_resolve(d,'upheld','ok',me); assert false; exception when others then assert sqlerrm like 'La disputa debe resolverla otra%',sqlerrm; end;
 perform plone27_dispute_resolve(d,'upheld','Se anula',ot); assert (select status from plone27_tax_receipts where id=rc)='rectified','disputa estimada anula el recibo';
 insert into plone27_policies(kind,name,scope,params,status,approved_by) values('debt_terms','Deuda','global','{"max_principal":50,"allow_partial":false}','published',ap);
 begin insert into plone27_debts(account_id,creditor_account,principal,reason,authorized_by) values(a,s,80,'x',ap); assert false; exception when others then assert sqlerrm like 'Supera el principal máximo%',sqlerrm; end;
 update plone27_settings set value='false' where key='late_penalty_enabled'; raise notice 'NORMAS OK'; end $$;
do $$ declare bk uuid; s uuid; pr uuid; j uuid; reg uuid; c uuid; r jsonb; begin
 select id into bk from plone27_banks where code='0001'; select id into s from plone27_accounts where name='Tesoreria';
 insert into plone27_customers(dip,full_name,bank_id) values('KID-0001','Peque',bk) returning id into c;
 insert into plone27_junior_profiles(customer_id,birth_date,guardian_user,per_tx_limit,daily_limit,monthly_limit) values(c,'2016-01-01',gen_random_uuid(),20,30,100);
 insert into plone27_products(code,bank_id,kind,name,monthly_fee,fee_account,requires_guardian,status,approved_by) values('JR',bk,'account_junior','Junior',3,s,true,'active',gen_random_uuid()) returning id into pr;
 begin insert into plone27_products(code,bank_id,kind,name,interest_rate,requires_guardian) values('JR2',bk,'account_junior','x',2,true); assert false; exception when check_violation then null; end;
 j:=(plone27_open_account_p(pr,'Kid2',null,null)->>'id')::uuid; update plone27_accounts set customer_id=c where id=j; perform plone27_transfer('jf',s,j,50,'',null);
 begin perform plone27_transfer('jx',j,s,5,'',null); assert false; exception when others then assert sqlerrm like 'Membresía Junior no vigente%',sqlerrm; end;
 r:=plone27_subscription_renew(j,null,null); assert (r->>'renewed')='true','membresía renovada';
 begin perform plone27_subscription_renew(j,null,null); assert false; exception when others then assert sqlerrm like 'Membresía vigente%',sqlerrm; end;
 perform plone27_transfer('jx',j,s,5,'',null);
 begin perform plone27_transfer('jy',j,s,25,'',null); assert false; exception when others then assert sqlerrm like 'Control parental: supera el límite por operación%',sqlerrm; end;
 reg:=(plone27_open_account(bk,'personal','Regular',null,null)->>'id')::uuid; perform plone27_transfer('jreg',s,reg,50,'',null);
 begin perform plone27_transfer('jz',reg,j,5,'',null); assert false; exception when others then assert sqlerrm like 'Cuenta Junior: no puede%',sqlerrm; end;
 begin perform plone27_transfer('jw',j,reg,5,'',null); assert false; exception when others then assert sqlerrm like 'Cuenta Junior: no puede%',sqlerrm; end;
 begin update plone27_accounts set allow_negative=true where id=j; assert false; exception when others then assert sqlerrm like 'Una cuenta Junior%',sqlerrm; end;
 begin perform plone27_issue_card(j,'credit',null,100,false,null); assert false; exception when others then assert sqlerrm like 'Una cuenta Junior no admite tarjeta%',sqlerrm; end;
 update plone27_subscriptions set period_end=current_date-10,status='active' where account_id=j; r:=plone27_subscriptions_sweep(null); assert (r->>'renewed')::int=1,'barrido renueva';
 update plone27_subscriptions set auto_renew=false,period_end=current_date-10,status='active' where account_id=j; r:=plone27_subscriptions_sweep(null); assert (r->>'expired')::int=1,'barrido expira';
 assert jsonb_array_length(plone27_integrity_report())>=12 and jsonb_array_length(plone27_security_report())>=7,'informes';
 assert (select (e->>'count')::int from jsonb_array_elements(plone27_security_report()) e where e->>'check'='Tablas sin RLS')=0,'RLS en todas las tablas';
 assert (select (e->>'count')::int from jsonb_array_elements(plone27_security_report()) e where e->>'check'='Funciones ejecutables por anon/authenticated')=0,'funciones cerradas';
 raise notice 'JUNIOR OK'; end $$;
