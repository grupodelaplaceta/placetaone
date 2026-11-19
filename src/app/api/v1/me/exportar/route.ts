import { sesionDe, respuesta } from "@/lib/sesion";
import { GET as perfil } from "../route";
import { GET as movimientos } from "../accounts/[iban]/transactions/route";

// Exportación de los datos del usuario (RGPD: acceso y portabilidad). Solo sus propios datos (me:read).
// Pagina todos los movimientos de cada cuenta con el mismo cursor de la API de movimientos (tope: 10.000 por cuenta).
const LOTE = 200;
const MAX_LOTES = 50;

export async function GET(req: Request) {
  const r = await sesionDe(req, "me:read");
  if ("err" in r) return r.err;
  const { s } = r;
  const autorizacion = req.headers.get("authorization") ?? "";
  const [cuentas, benef, sesiones] = await Promise.all([
    s.db.rpc("plone27_user_accounts", { p_user: s.usuario, p_bank: s.banco }),
    s.db.rpc("plone27_user_beneficiaries", { p_user: s.usuario, p_bank: s.banco }),
    s.db.rpc("plone27_user_sessions_list", { p_user: s.usuario }),
  ]);
  if (cuentas.error || benef.error || sesiones.error) return respuesta(req, { error: "No se puede generar la exportación" }, 422, s.cliente);
  const lista: { id: string; iban: string }[] = Array.isArray(cuentas.data) ? cuentas.data : [];
  const cuentasExp = [];
  for (const c of lista) {
    const det = await s.db.rpc("plone27_user_account_detail", { p_user: s.usuario, p_account: c.id, p_bank: s.banco });
    const tarj = await s.db.rpc("plone27_user_cards", { p_user: s.usuario, p_bank: s.banco, p_iban: c.iban });
    const movs: unknown[] = [];
    let antes: string | null = null;
    let completo = false;
    for (let i = 0; i < MAX_LOTES; i++) {
      const u = new URL(req.url);
      u.searchParams.set("limite", String(LOTE));
      if (antes) u.searchParams.set("antes", antes); else u.searchParams.delete("antes");
      const res = await movimientos(new Request(u.toString(), { headers: { authorization: autorizacion } }), { params: Promise.resolve({ iban: c.iban }) });
      const j = await res.json().catch(() => ({}));
      const lote: unknown[] = Array.isArray(j.movimientos) ? j.movimientos : [];
      movs.push(...lote);
      if (!j.siguiente || lote.length === 0) { completo = true; break; }
      antes = String(j.siguiente);
    }
    cuentasExp.push({ cuenta: det.data ?? null, tarjetas: tarj.data ?? [], movimientos: movs, movimientos_completos: completo });
  }
  const perJson = await (await perfil(new Request(req.url, { headers: { authorization: autorizacion } }))).json().catch(() => ({}));
  return respuesta(req, {
    exportado_en: new Date().toISOString(),
    perfil: perJson,
    cuentas: cuentasExp,
    beneficiarios: benef.data ?? [],
    sesiones: sesiones.data ?? [],
  }, 200, s.cliente);
}
