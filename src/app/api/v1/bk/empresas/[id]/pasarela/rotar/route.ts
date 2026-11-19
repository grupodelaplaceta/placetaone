import { clientFrom } from "@/lib/apikey";
import { personaPorDip, rotarClaveEmpresa } from "@/lib/empresas";

// Rotar la clave de la pasarela de una empresa (empresas:gestionar). Lo pide un titular de la empresa.
// Body: { dip_actor }. La clave nueva se devuelve una sola vez y la anterior deja de valer.
export async function POST(req: Request, { params }: { params: Promise<{ id: string }> }) {
  const a = await clientFrom(req, "empresas:gestionar");
  if (a.err) return Response.json({ error: "Denegado" }, { status: a.err });
  const { id } = await params;
  const b = await req.json().catch(() => null);
  try {
    const actor = await personaPorDip(a.db, String(b?.dip_actor ?? ""));
    const r = await rotarClaveEmpresa(a.db, a.c.bank_id, id, actor);
    return Response.json({ ...r, aviso: "Guarda la clave ahora: no se vuelve a mostrar. La anterior ya no funciona." });
  } catch (e) {
    return Response.json({ error: (e as Error).message }, { status: 422 });
  }
}
