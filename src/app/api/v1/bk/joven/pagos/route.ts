import { clientFrom } from "@/lib/apikey";

// Compra de Placeta Joven en un comercio Joven, con IVA desglosado (joven:gestionar).
// Cabecera Idempotency-Key obligatoria (8 a 80 caracteres).
// Body: { joven_iban | dip, comercio_iban, importe, concepto? }. Sin joven_iban, usa la cuenta Joven del dip.
export async function POST(req: Request) {
  const a = await clientFrom(req, "joven:gestionar");
  if (a.err) return Response.json({ error: "Denegado" }, { status: a.err });
  const clave = req.headers.get("idempotency-key") ?? "";
  if (!/^[A-Za-z0-9_-]{8,80}$/.test(clave)) return Response.json({ error: "Idempotency-Key obligatoria (8 a 80 caracteres)" }, { status: 400 });
  const b = (await req.json().catch(() => null)) as Record<string, unknown> | null;
  let joven = b?.joven_iban ? String(b.joven_iban) : "";
  if (!joven && b?.dip) {
    const r = await a.db.rpc("plone27_joven_cuenta_de", { p_bank: a.c.bank_id, p_dip: String(b.dip) });
    const iban = (r.data as { iban?: string } | null)?.iban;
    if (!iban) return Response.json({ error: "Esta persona no tiene cuenta Placeta Joven en tu entidad" }, { status: 404 });
    joven = iban;
  }
  const { data, error } = await a.db.rpc("plone27_joven_pagar", {
    p_bank: a.c.bank_id, p_joven_iban: joven, p_comercio_iban: String(b?.comercio_iban ?? ""),
    p_importe: Number(b?.importe), p_concepto: b?.concepto ? String(b.concepto) : null, p_clave: clave, p_actor: null,
  });
  if (error) return Response.json({ error: error.message }, { status: 422 });
  const repetida = (data as { repetida?: boolean } | null)?.repetida === true;
  return Response.json(data, { status: repetida ? 200 : 201 });
}
