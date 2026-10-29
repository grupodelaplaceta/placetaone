import { randomBytes, randomUUID } from "crypto";
import { staffFrom } from "@/lib/supabase";
import { hashKey } from "@/lib/apikey";
import { SCOPE_KEYS } from "@/lib/scopes";
// API de gestión: recursos permitidos, columnas editables y roles. El servidor fija actor, aprobador, claves y secretos.
type Cfg = { table: string; sel: string; read: string[]; write: string[]; create?: string[]; update?: string[]; bank?: string; pk?: string; order?: string; desc?: string; shared?: boolean };
const ALL = ["auditor", "financiero", "fiscal", "financiacion", "gestor_bancario", "aprobador"], BK = ["gestor_bancario", "financiero"];
const R: Record<string, Cfg> = {
  banks: { table: "plone27_banks", sel: "id,code,name,description,status,valid_from,valid_to", read: ALL, write: BK, create: ["name", "description"], update: ["name", "description", "status", "valid_to"], bank: "id", order: "code" },
  accounts: { table: "plone27_accounts", sel: "id,iban,name,kind,status,daily_limit,bank_id", read: ALL, write: BK, create: ["bank_id", "name", "kind", "product_id"], update: ["name", "status", "daily_limit"], bank: "bank_id", order: "iban" },
  clients: { table: "plone27_api_clients", sel: "id,name,scopes,rate_limit,active,bank_id,created_at", read: ALL, write: BK, create: ["bank_id", "name", "scopes", "rate_limit"], update: ["name", "scopes", "rate_limit", "active"], bank: "bank_id" },
  webhooks: { table: "plone27_webhooks", sel: "id,url,events,active,bank_id", read: ALL, write: BK, create: ["bank_id", "url", "events"], update: ["url", "events", "active"], bank: "bank_id" },
  fees: { table: "plone27_fee_rules", sel: "id,op_type,method,rate,min_amount,max_amount,payer,valid_from,valid_to,bank_id", read: ALL, write: BK, create: ["bank_id", "op_type", "method", "rate", "min_amount", "max_amount", "payer", "bank_pay_account", "beneficiary_account", "valid_from", "valid_to"], update: ["rate", "payer", "valid_to"], bank: "bank_id" },
  taxrules: { table: "plone27_tax_rules", sel: "id,code,name,max_rate,collector_account", read: ALL, write: ["fiscal"], create: ["code", "name", "max_rate", "collector_account"], update: ["name", "max_rate", "collector_account"], order: "code" },
  taxversions: { table: "plone27_tax_rule_versions", sel: "id,rule_id,version,method,rate,min_amount,max_amount,valid_from,valid_to,status,retro_mode,reason,scope_op", read: ALL, write: ["fiscal"], create: ["rule_id", "method", "rate", "min_amount", "max_amount", "valid_from", "valid_to", "retro_mode", "reason", "scope_bank", "scope_op"], update: ["valid_to"], order: "version" },
  products: { table: "plone27_products", sel: "id,code,kind,name,status,daily_limit,monthly_fee,interest_rate,min_age,valid_from,valid_to,bank_id", read: ALL, write: BK, create: ["code", "bank_id", "kind", "name", "description", "daily_limit", "credit_limit", "monthly_fee", "fee_account", "interest_rate", "min_age", "requires_guardian", "valid_from", "valid_to"], update: ["name", "description", "status", "daily_limit", "monthly_fee", "valid_to"], bank: "bank_id", order: "code" },
  carddesigns: { table: "plone27_card_designs", sel: "id,name,tier,price,license_fee,status,revenue_account", read: ALL, write: ["gestor_bancario", "aprobador"], create: ["name", "tier", "price", "license_fee", "revenue_account"], update: [], shared: true },
  cards: { table: "plone27_cards", sel: "id,card_ref,account_id,kind,status,is_test,expires,last4,credit_limit", read: ALL, write: BK, create: ["account_id", "kind", "credit_limit", "is_test"], update: [] },
  transactions: { table: "plone27_transactions", sel: "id,ref,transfer_ref,kind,status,memo,created_at", read: ALL, write: BK, create: ["from_account", "to_account", "amount", "memo"], update: [], desc: "created_at" },
  scheduled: { table: "plone27_scheduled", sel: "id,from_account,to_account,amount,run_at,recurrence,status,memo", read: ALL, write: ["financiero"], create: ["from_account", "to_account", "amount", "run_at", "recurrence", "memo"], update: ["status"] },
  batches: { table: "plone27_batches", sel: "id,kind,from_account,status", read: ALL, write: ["financiero"], create: ["kind", "from_account"], update: [] },
  batchitems: { table: "plone27_batch_items", sel: "id,batch_id,to_account,amount,status,error", read: ALL, write: ["financiero"], create: ["batch_id", "to_account", "amount"], update: [] },
  grantprograms: { table: "plone27_grant_programs", sel: "id,name,kind,budget,funding_account", read: ALL, write: ["financiacion"], create: ["name", "kind", "budget", "funding_account"], update: ["name", "budget"], shared: true },
  grants: { table: "plone27_grants", sel: "id,ref,program_id,beneficiary_account,granted,approved,paid", read: ALL, write: ["financiacion"], create: ["program_id", "beneficiary_account", "granted"], update: [], desc: "ref" },
  justifications: { table: "plone27_justifications", sel: "id,ref,grant_id,transaction_id,invoice_ref,amount,status,reimb_ref", read: ALL, write: ["financiacion", "financiero"], create: ["grant_id", "transaction_id", "invoice_ref", "amount"], update: ["status"], desc: "ref" },
  budgets: { table: "plone27_budgets", sel: "id,name,period,approved,committed,executed,restricted", read: ALL, write: ["financiero"], create: ["name", "period", "approved", "restricted"], update: ["approved", "committed", "executed"], shared: true },
  debts: { table: "plone27_debts", sel: "id,ref,account_id,creditor_account,principal,authorized_charges,paid,due_date,disputed", read: ALL, write: ["financiero"], create: ["account_id", "creditor_account", "principal", "due_date", "reason"], update: ["disputed", "authorized_charges", "due_date"], desc: "ref" },
  invoices: { table: "plone27_invoices", sel: "id,ref,account_id,concept,amount,status", read: ALL, write: ["financiero", "fiscal"], create: ["account_id", "concept", "amount"], update: ["status"], desc: "ref" },
  receipts: { table: "plone27_tax_receipts", sel: "id,ref,account_id,amount,paid_amount,status,due_date,disputed,created_at", read: ALL, write: ["fiscal", "financiero"], update: ["disputed"], desc: "created_at" },
  exemptions: { table: "plone27_tax_exemptions", sel: "id,rule_id,account_id,valid_from,valid_to,reason,legal_basis", read: ALL, write: ["fiscal"], create: ["rule_id", "account_id", "valid_from", "valid_to", "reason", "legal_basis"], update: ["valid_to"], shared: true },
  distribution: { table: "plone27_tax_distribution", sel: "id,rule_id,account_id,pct", read: ALL, write: ["fiscal"], create: ["rule_id", "account_id", "pct"], update: ["pct"], shared: true },
  settlements: { table: "plone27_settlements", sel: "id,ref,bank_id,period_from,period_to,evaluated,collected,pending,refunded", read: ALL, write: ["fiscal", "financiero"], create: ["bank_id", "period_from", "period_to"], update: [], bank: "bank_id", desc: "ref" },
  incidents: { table: "plone27_incidents", sel: "id,ref,kind,status,at,detail", read: ALL, write: ["financiero", "fiscal", "aprobador"], update: ["status"], desc: "at" },
  approvals: { table: "plone27_approvals", sel: "id,ref,subject,subject_id,reason,result,at", read: ALL, write: ["aprobador"], update: [], desc: "at" },
  audit: { table: "plone27_audit_log", sel: "id,actor,action,entity,entity_id,at", read: ["auditor", "aprobador", "financiero"], write: [], desc: "id", shared: true },
  numbering: { table: "plone27_numbering_formats", sel: "kind,version,prefix,year_scoped,width,status", read: ALL, write: [], order: "kind", shared: true },
  outbox: { table: "plone27_outbox", sel: "id,event,status,attempts,created_at", read: ["auditor", "financiero"], write: [], desc: "id", shared: true },
  balances: { table: "plone27_account_balances", sel: "account_id,name,kind,status,booked,reserved,bank_id", read: ALL, write: [], bank: "bank_id", order: "name" },
  ledger: { table: "plone27_ledger_entries", sel: "id,transaction_id,account_id,direction,amount,created_at", read: ALL, write: [], desc: "id" },
  members: { table: "plone27_account_members", sel: "account_id,user_id,role", read: ALL, write: BK, create: ["account_id", "user_id", "role"], update: ["role"] },
  juniors: { table: "plone27_juniors", sel: "account_id,birth_date,guardian_user,per_tx_limit", read: ALL, write: BK, create: ["account_id", "birth_date", "guardian_user", "per_tx_limit"], update: ["per_tx_limit", "guardian_user"], pk: "account_id" },
  brackets: { table: "plone27_tax_brackets", sel: "version_id,from_amount,to_amount,rate", read: ALL, write: ["fiscal"], create: ["version_id", "from_amount", "to_amount", "rate"], update: [], shared: true, order: "from_amount" },
  staff: { table: "plone27_staff", sel: "user_id,role,active,bank_id", read: ["aprobador"], write: [], create: ["user_id", "role", "bank_id"], update: ["role", "active", "bank_id"], pk: "user_id" },
};
type Ctx = { params: Promise<{ res: string }> };
const J = (e: string, st = 400) => Response.json({ error: e }, { status: st });
const pick = (b: Record<string, unknown>, k: string[]) => Object.fromEntries(Object.entries(b).filter(([x, v]) => k.includes(x) && v !== "" && v !== undefined));

const badScopes = (sc: unknown) => Array.isArray(sc) && !sc.every(x => SCOPE_KEYS.includes(x));
const scoped = (s: { bank: string | null }, c: Cfg) => !!s.bank && !c.bank && !c.shared;
export async function GET(req: Request, { params }: Ctx) {
  const c = R[(await params).res]; if (!c) return J("Recurso desconocido", 404);
  const s = await staffFrom(req, c.read); if (!s) return J("No autorizado", 403);
  if (scoped(s, c)) return J("Solo personal global", 403);
  let q = s.db.from(c.table).select(c.sel); const u = new URL(req.url);
  for (const k of ["bank_id", "rule_id", "batch_id", "grant_id", "program_id", "account_id", "version_id"]) { const v = u.searchParams.get(k); if (v) q = q.eq(k, v); }
  if (s.bank && c.bank) q = q.eq(c.bank, s.bank);
  const r = c.desc ? await q.order(c.desc, { ascending: false }).limit(300) : c.order ? await q.order(c.order).limit(500) : await q.limit(500);
  return r.error ? J(r.error.message, 500) : Response.json(r.data);
}
export async function POST(req: Request, { params }: Ctx) {
  const name = (await params).res, c = R[name]; if (!c?.create) return J("Recurso desconocido", 404);
  const s = await staffFrom(req, c.write); if (!s) return J("No autorizado", 403);
  const f = pick((await req.json().catch(() => ({}))) as Record<string, unknown>, c.create);
  if (scoped(s, c)) return J("Solo personal global", 403);
  if (s.bank) { if (name === "banks") return J("Solo personal global crea entidades", 403); if (c.create.includes("bank_id")) f.bank_id = s.bank; }
  if (badScopes(f.scopes)) return J("Scope desconocido");
  let secret: string | undefined, row: unknown;
  if (name === "banks") {
    const { data, error } = await s.db.rpc("plone27_open_bank", { p_name: f.name, p_actor: s.id }); if (error) return J(error.message, 422);
    if (f.description) await s.db.from(c.table).update({ description: f.description }).eq("id", data.id); row = data;
  } else if (name === "accounts" && f.product_id) {
    const { data, error } = await s.db.rpc("plone27_open_account_p", { p_product: f.product_id, p_name: f.name, p_owner: null, p_actor: s.id }); if (error) return J(error.message, 422); row = data;
  } else if (name === "transactions" || name === "cards" || name === "settlements") {
    const [fn, args]: [string, Record<string, unknown>] = name === "transactions" ? ["plone27_transfer_fee", { p_key: randomUUID(), p_from: f.from_account, p_to: f.to_account, p_amount: f.amount, p_memo: f.memo ?? null }]
      : name === "cards" ? ["plone27_issue_card", { p_account: f.account_id, p_kind: f.kind, p_design: null, p_limit: f.credit_limit ?? null, p_test: !!f.is_test }] : ["plone27_settle_bank", { p_bank: f.bank_id, p_from: f.period_from, p_to: f.period_to }];
    const { data, error } = await s.db.rpc(fn, { ...args, p_actor: s.id }); if (error) return J(error.message, 422); row = data; if (name === "cards" && data?.test_number) secret = "Número de PRUEBA (no se guarda): " + data.test_number;
  } else if (name === "accounts") {
    const { data, error } = await s.db.rpc("plone27_open_account", { p_bank: f.bank_id, p_kind: f.kind, p_name: f.name, p_owner: null, p_actor: s.id }); if (error) return J(error.message, 422); row = data;
  } else {
    if (name === "webhooks") { secret = randomBytes(24).toString("hex"); f.secret = secret; }
    if (name === "clients") { secret = "plk_" + randomBytes(24).toString("hex"); f.key_hash = hashKey(secret); if (!f.scopes) f.scopes = ["accounts:read", "transfers:write"]; }
    if (["fees", "distribution"].includes(name)) f.approved_by = s.id;
    if (name === "products") f.created_by = s.id;
    if (name === "debts") { f.authorized_by = s.id; if (!f.reason) f.reason = "alta"; }
    if (name === "exemptions") f.approved_by = s.id;
    if (name === "taxversions") { const m = await s.db.from(c.table).select("version").eq("rule_id", f.rule_id as string).order("version", { ascending: false }).limit(1); f.version = ((m.data?.[0]?.version as number) ?? 0) + 1; f.author = s.id; if (!f.reason) f.reason = "alta"; }
    const q = name === "staff" ? s.db.from(c.table).upsert(f) : s.db.from(c.table).insert(f);
    const { data, error } = await q.select().single(); if (error) return J(error.message, 422);
    row = data; if (name === "clients" && data) delete (data as Record<string, unknown>).key_hash;
  }
  await s.db.from("plone27_audit_log").insert({ actor: s.id, action: "admin_create", entity: name, detail: { ...f, key_hash: undefined, secret: undefined } });
  return Response.json({ row, secret });
}
export async function DELETE(req: Request, { params }: Ctx) {
  const name = (await params).res; if (name !== "members") return J("No permitido", 405);
  const s = await staffFrom(req, R.members.write); if (!s) return J("No autorizado", 403); if (scoped(s, R.members)) return J("Solo personal global", 403);
  const u = new URL(req.url), a = u.searchParams.get("account_id"), uu = u.searchParams.get("user_id"); if (!a || !uu) return J("Faltan datos");
  const { error } = await s.db.from(R.members.table).delete().eq("account_id", a).eq("user_id", uu); if (error) return J(error.message, 422);
  await s.db.from("plone27_audit_log").insert({ actor: s.id, action: "admin_delete", entity: "members", entity_id: a, detail: { user_id: uu } }); return Response.json({ ok: true });
}
export async function PATCH(req: Request, { params }: Ctx) {
  const name = (await params).res, c = R[name]; if (!c?.update) return J("Recurso desconocido", 404);
  const s = await staffFrom(req, c.write); if (!s) return J("No autorizado", 403);
  if (scoped(s, c)) return J("Solo personal global", 403);
  const id = new URL(req.url).searchParams.get("id"); if (!id) return J("Falta id");
  const b = (await req.json().catch(() => ({}))) as Record<string, unknown>;
  const K = (p: string) => p + ":" + id;                                         // claves deterministas: un doble clic no duplica
  const rpc: Record<string, [string, Record<string, unknown>] | null> = {
    carddesigns: b.status ? ["plone27_design_step", { p_design: id, p_to: b.status }] : null,
    cards: b.status ? ["plone27_card_set_status", { p_card: id, p_to: b.status }] : null,
    batches: b.run ? ["plone27_run_batch", { p_batch: id }] : null,
    justifications: b.reimburse ? ["plone27_reimburse", { p_key: K("ui-reimb"), p_just: id }] : null,
    transactions: b.reverse ? ["plone27_reverse", { p_key: K("ui-rev"), p_tx: id, p_reason: "Reversión desde el panel" }] : null,
    receipts: b.pay ? ["plone27_tax_pay", { p_key: K("ui-pay"), p_receipt: id }] : null,
    approvals: b.approve !== undefined ? ["plone27_approval_decide", { p_id: id, p_approve: b.approve }] : null };
  if (rpc[name]) { const { data, error } = await s.db.rpc(rpc[name]![0], { ...rpc[name]![1], p_actor: s.id }); if (error) return J(error.message, 422); await s.db.from("plone27_audit_log").insert({ actor: s.id, action: "admin_" + rpc[name]![0], entity: name, entity_id: id }); return Response.json({ ok: true, result: data }); } let f: Record<string, unknown> = pick(b, c.update);
  if ((name === "banks" || name === "products") && f.status === "active") f.approved_by = s.id;                       // activar exige aprobación registrada
  if (name === "taxversions" && b.publish) f = { status: "published", approver: s.id, published_at: new Date().toISOString() };
  if (badScopes(f.scopes)) return J("Scope desconocido");
  if (!Object.keys(f).length) return J("Nada que actualizar");
  let q = s.db.from(c.table).update(f).eq(c.pk ?? "id", id); if (s.bank && c.bank) q = q.eq(c.bank, s.bank);
  const { error } = await q; if (error) return J(error.message, 422);
  await s.db.from("plone27_audit_log").insert({ actor: s.id, action: "admin_update", entity: name, entity_id: id, detail: f });
  return Response.json({ ok: true });
}
