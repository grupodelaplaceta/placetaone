import { clientFrom } from "@/lib/apikey";

// Pagos pendientes de confirmación por el banco pagador (pagos:resolver).
export async function GET(req: Request) {
  const a = await clientFrom(req, "pagos:resolver");
  if (a.err) return Response.json({ error: "Denegado" }, { status: a.err });
  const { data, error } = await a.db.rpc("plone27_bk_pagos_pendientes", { p_bank: a.c.bank_id });
  if (error) return Response.json({ error: "No se pueden cargar los pagos" }, { status: 422 });
  return Response.json({ pagos: data ?? [] });
}
