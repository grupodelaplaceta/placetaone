import { clientFrom } from "@/lib/apikey";
// Reglas de uso (politicas:gestionar). Sin regla = sin restricción.
// Body: { ambito: "rbu" | "programa", programa?: id, tipos?: ["personal","business",…], comercios?: [id de cuenta de empresa], categorias?: ["alimentacion",…] }
// Cada filtro configurado debe cumplirse. Una regla nueva sustituye a la activa del mismo ámbito.
export async function GET(req: Request) {
  const a = await clientFrom(req, "politicas:gestionar");
  if (a.err) return Response.json({ error: "Denegado" }, { status: a.err });
  const { data, error } = await a.db.rpc("plone27_bk_politicas", { p_bank: a.c.bank_id });
  if (error) return Response.json({ error: "No se pueden listar las reglas" }, { status: 422 });
  return Response.json({ politicas: data ?? [] });
}
export async function POST(req: Request) {
  const a = await clientFrom(req, "politicas:gestionar");
  if (a.err) return Response.json({ error: "Denegado" }, { status: a.err });
  const b = await req.json().catch(() => null);
  const arr = (v: unknown) => (Array.isArray(v) ? v.map(String) : []);
  const { data, error } = await a.db.rpc("plone27_bk_politica_crear", { p_bank: a.c.bank_id, p_ambito: String(b?.ambito ?? ""),
    p_programa: b?.programa ? String(b.programa) : null, p_tipos: arr(b?.tipos), p_comercios: arr(b?.comercios), p_categorias: arr(b?.categorias), p_actor: null });
  if (error) return Response.json({ error: error.message }, { status: 422 });
  return Response.json({ politica: data }, { status: 201 });
}
