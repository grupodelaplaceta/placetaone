import { clientFrom } from "@/lib/apikey";

// Producto pasarela de la entidad: activa o no, validez por defecto, importe máximo y tipos de cuenta que puede cobrar (pasarela:configurar).
export async function GET(req: Request) {
  const a = await clientFrom(req, "pasarela:configurar");
  if (a.err) return Response.json({ error: "Denegado" }, { status: a.err });
  const { data, error } = await a.db.from("plone27_pasarela_config").select("activa,minutos_defecto,importe_maximo,destinos").eq("bank_id", a.c.bank_id).maybeSingle();
  if (error) return Response.json({ error: "No se puede consultar" }, { status: 422 });
  return Response.json(data ?? { activa: false, minutos_defecto: 15, importe_maximo: 50000, destinos: ["business", "system"] });
}

// Body: { activa, minutos_defecto?, importe_maximo?, destinos?: ["business" | "system"] }
export async function PUT(req: Request) {
  const a = await clientFrom(req, "pasarela:configurar");
  if (a.err) return Response.json({ error: "Denegado" }, { status: a.err });
  const b = await req.json().catch(() => null);
  const destinos = Array.isArray(b?.destinos) ? b.destinos.map(String) : ["business", "system"];
  const { error } = await a.db.rpc("plone27_bk_pasarela_set", { p_bank: a.c.bank_id, p_activa: Boolean(b?.activa),
    p_minutos: b?.minutos_defecto == null ? 15 : Number(b.minutos_defecto), p_importe_max: b?.importe_maximo == null ? 50000 : Number(b.importe_maximo),
    p_destinos: destinos });
  if (error) return Response.json({ error: error.message }, { status: 422 });
  return Response.json({ configurada: true });
}
