import { clientFrom } from "@/lib/apikey";

// Identificador y enlace NFC de una tarjeta física o virtual (tarjetas:gestionar).
// PUT body: { nfc_id?: "8–64 caracteres A-Z a-z 0-9 : _ -", enlace?: "https://…" }. Campos vacíos los borran.
export async function GET(req: Request, { params }: { params: Promise<{ ref: string }> }) {
  const a = await clientFrom(req, "tarjetas:gestionar");
  if (a.err) return Response.json({ error: "Denegado" }, { status: a.err });
  const { ref } = await params;
  const { data, error } = await a.db.rpc("plone27_tarjeta_nfc_get", { p_bank: a.c.bank_id, p_ref: ref });
  if (error) return Response.json({ error: "No se puede consultar" }, { status: 422 });
  if (!data) return Response.json({ error: "Tarjeta no encontrada" }, { status: 404 });
  return Response.json(data);
}

export async function PUT(req: Request, { params }: { params: Promise<{ ref: string }> }) {
  const a = await clientFrom(req, "tarjetas:gestionar");
  if (a.err) return Response.json({ error: "Denegado" }, { status: a.err });
  const { ref } = await params;
  const b = await req.json().catch(() => null);
  const { error } = await a.db.rpc("plone27_tarjeta_nfc_set", { p_bank: a.c.bank_id, p_ref: ref, p_nfc: String(b?.nfc_id ?? ""),
    p_enlace: String(b?.enlace ?? ""), p_actor: null });
  if (error) return Response.json({ error: error.message }, { status: 422 });
  return Response.json({ actualizado: true });
}
