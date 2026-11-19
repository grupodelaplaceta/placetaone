import { clientFrom } from "@/lib/apikey";

// Restricciones de pago del banco (pagos:restringir): medios, tipos de tarjeta, modalidades y operaciones que no permite a sus clientes.
// tipo: medio (cuenta | tarjeta) · tarjeta (digital | physical | credit | prepago) · modalidad (inmediata | diferida) · operacion (interbancario)
export async function GET(req: Request) {
  const a = await clientFrom(req, "pagos:restringir");
  if (a.err) return Response.json({ error: "Denegado" }, { status: a.err });
  const { data, error } = await a.db.from("plone27_restricciones_pago").select("tipo,valor,bloqueado").eq("bank_id", a.c.bank_id);
  if (error) return Response.json({ error: "No se pueden consultar" }, { status: 422 });
  return Response.json({ restricciones: data ?? [] });
}

// Body: { tipo, valor, bloqueado: true | false }
export async function PUT(req: Request) {
  const a = await clientFrom(req, "pagos:restringir");
  if (a.err) return Response.json({ error: "Denegado" }, { status: a.err });
  const b = await req.json().catch(() => null);
  const { error } = await a.db.rpc("plone27_bk_restriccion_set", { p_bank: a.c.bank_id, p_tipo: String(b?.tipo ?? ""), p_valor: String(b?.valor ?? ""), p_bloqueado: Boolean(b?.bloqueado) });
  if (error) return Response.json({ error: error.message }, { status: 422 });
  return Response.json({ configurada: true });
}
