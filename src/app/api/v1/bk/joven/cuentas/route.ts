import { clientFrom } from "@/lib/apikey";

// Cuenta Placeta Joven de una persona (joven:gestionar).
// GET ?dip=…  → la cuenta de esa persona, para que el portal la seleccione sola.
// POST { dip } → la crea a nombre del DIP (si ya existe, devuelve la existente).
export async function GET(req: Request) {
  const a = await clientFrom(req, "joven:gestionar");
  if (a.err) return Response.json({ error: "Denegado" }, { status: a.err });
  const dip = new URL(req.url).searchParams.get("dip") ?? "";
  const { data, error } = await a.db.rpc("plone27_joven_cuenta_de", { p_bank: a.c.bank_id, p_dip: dip });
  if (error) return Response.json({ error: error.message }, { status: 422 });
  if (!data) return Response.json({ error: "Esta persona no tiene cuenta Placeta Joven en tu entidad" }, { status: 404 });
  return Response.json(data);
}

export async function POST(req: Request) {
  const a = await clientFrom(req, "joven:gestionar");
  if (a.err) return Response.json({ error: "Denegado" }, { status: a.err });
  const b = (await req.json().catch(() => null)) as Record<string, unknown> | null;
  const nacimiento = String(b?.fecha_nacimiento ?? "");
  if (!/^\d{4}-\d{2}-\d{2}$/.test(nacimiento)) return Response.json({ error: "fecha_nacimiento debe ser AAAA-MM-DD" }, { status: 400 });
  const { data, error } = await a.db.rpc("plone27_joven_alta", { p_bank: a.c.bank_id, p_dip: String(b?.dip ?? ""), p_nacimiento: nacimiento, p_actor: null });
  if (error) return Response.json({ error: error.message }, { status: 422 });
  const creada = (data as { creada?: boolean } | null)?.creada === true;
  return Response.json(data, { status: creada ? 201 : 200 });
}
