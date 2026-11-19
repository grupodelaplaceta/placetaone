import { clientFrom } from "@/lib/apikey";

// Tasas de la entidad sobre sus pasarelas y comercios (tasas:gestionar).
// La entidad solo puede cobrar tasas a sus comercios para su propio beneficio (pagador comercio, beneficiario banco).
export async function GET(req: Request) {
  const a = await clientFrom(req, "tasas:gestionar");
  if (a.err) return Response.json({ error: "Denegado" }, { status: a.err });
  const { data, error } = await a.db.rpc("plone27_tasas_listar", { p_bank: a.c.bank_id });
  if (error) return Response.json({ error: "No se pueden listar las tasas" }, { status: 422 });
  return Response.json({ tasas: data ?? [] });
}

// Body: { tipo: "fijo" | "porcentaje", valor, minimo?, maximo?, medio?: "cuenta" | "tarjeta", client_id?, pagador: "comercio", beneficiario: "banco" }
export async function POST(req: Request) {
  const a = await clientFrom(req, "tasas:gestionar");
  if (a.err) return Response.json({ error: "Denegado" }, { status: a.err });
  const b = await req.json().catch(() => null);
  const { data, error } = await a.db.rpc("plone27_tasa_alta", { p_bank: a.c.bank_id, p_ambito: "banco", p_client: b?.client_id ? String(b.client_id) : null,
    p_medio: b?.medio ? String(b.medio) : null, p_tipo: String(b?.tipo ?? ""), p_valor: Number(b?.valor), p_minimo: b?.minimo == null ? 0 : Number(b.minimo),
    p_maximo: b?.maximo == null ? null : Number(b.maximo), p_pagador: String(b?.pagador ?? "comercio"), p_beneficiario: String(b?.beneficiario ?? "banco"), p_actor: null });
  if (error) return Response.json({ error: error.message }, { status: 422 });
  return Response.json({ tasa: data }, { status: 201 });
}
