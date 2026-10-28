import { staffFrom } from "@/lib/supabase";
// Pasarela única: allowlist de funciones y roles. El actor siempre lo fija el servidor.
const ALLOW: Record<string, string[]> = {
  plone27_transfer_fee: ["financiero", "gestor_bancario"], plone27_reverse: ["financiero", "aprobador"],
  plone27_tax_issue: ["fiscal"], plone27_tax_pay: ["fiscal", "financiero"],
  plone27_adjust_simulate: ["fiscal"], plone27_adjust_approve: ["aprobador"], plone27_adjust_execute: ["fiscal", "aprobador"],
  plone27_design_step: ["gestor_bancario", "aprobador"], plone27_design_buy: ["gestor_bancario", "financiero"],
  plone27_card_authorize: ["gestor_bancario"], plone27_card_settle: ["gestor_bancario"], plone27_card_close_cycle: ["gestor_bancario", "financiero"],
  plone27_run_scheduled: ["financiero"],
  plone27_open_bank: [],
  plone27_staff_set: [], plone27_tax_pay_partial: ["fiscal", "financiero"], plone27_approval_request: ["financiero", "fiscal", "gestor_bancario"], plone27_approval_decide: ["aprobador"], plone27_run_batch: ["financiero"], plone27_settle_bank: ["fiscal", "financiero"], plone27_debt_pay: ["financiero"], plone27_card_order_step: ["gestor_bancario"], plone27_cash_forecast: ["financiero", "auditor"], plone27_open_account: ["gestor_bancario"], plone27_issue_card: ["gestor_bancario"], plone27_card_set_status: ["gestor_bancario"], plone27_card_renew: ["gestor_bancario"],
  plone27_numbering_propose: [], plone27_numbering_simulate: ["aprobador"], plone27_numbering_publish: ["aprobador"], plone27_justify: ["financiacion"], plone27_reimburse: ["financiacion", "financiero"],
};
export async function POST(req: Request, { params }: { params: Promise<{ fn: string }> }) {
  const { fn } = await params; const roles = ALLOW[fn];
  if (!roles) return Response.json({ error: "Función desconocida" }, { status: 404 });
  const s = await staffFrom(req, roles);
  if (!s) return Response.json({ error: "No autorizado" }, { status: 403 });
  const body = await req.json().catch(() => ({}));
  const args: Record<string, unknown> = { ...body, p_actor: s.id };
  const key = req.headers.get("idempotency-key"); if (key) args.p_key = key;
  if (s.bank) { // personal limitado a una entidad: solo opera dentro de ella
    const bank = (args.p_bank as string) ?? (args.p_account ? (await s.db.from("plone27_accounts").select("bank_id").eq("id", args.p_account as string).maybeSingle()).data?.bank_id : null);
    if (bank && bank !== s.bank) return Response.json({ error: "Fuera de su entidad" }, { status: 403 });
  }
  const { data, error } = await s.db.rpc(fn, args);
  return error ? Response.json({ error: error.message }, { status: 422 }) : Response.json({ result: data });
}
