import { clientFrom } from "@/lib/apikey";

// Lectura de una cuenta Placeta Joven por IBAN (joven:leer). Solo lectura, de cualquier banco con el permiso.
// Devuelve estado, si está congelada y el disponible. No devuelve el DIP.
export async function GET(req: Request, { params }: { params: Promise<{ iban: string }> }) {
  const a = await clientFrom(req, "joven:leer");
  if (a.err) return Response.json({ error: "Denegado" }, { status: a.err });
  const { iban } = await params;
  const { data, error } = await a.db.rpc("plone27_joven_leer", { p_iban: iban });
  if (error) return Response.json({ error: error.message }, { status: 422 });
  if (!data) return Response.json({ error: "Cuenta Placeta Joven no encontrada" }, { status: 404 });
  return Response.json(data);
}
