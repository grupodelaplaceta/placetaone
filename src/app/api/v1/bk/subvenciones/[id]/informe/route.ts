import { clientFrom } from "@/lib/apikey";
import { generarPdf } from "@/lib/pdf";
import { lineasInforme, subvencionDeBanco, type Informe } from "@/lib/subvenciones";

// Informe de justificación de una subvención de la entidad (subvenciones:gestionar). Query: formato=json | pdf
export async function GET(req: Request, { params }: { params: Promise<{ id: string }> }) {
  const a = await clientFrom(req, "subvenciones:gestionar");
  if (a.err) return Response.json({ error: "Denegado" }, { status: a.err });
  const { id } = await params;
  if (!(await subvencionDeBanco(a.db, a.c.bank_id, id))) return Response.json({ error: "Subvención no encontrada en tu entidad" }, { status: 404 });
  const formato = new URL(req.url).searchParams.get("formato") ?? "json";
  const { data, error } = await a.db.rpc("plone27_grant_informe", { p_grant: id });
  if (error) return Response.json({ error: error.message }, { status: 422 });
  if (formato !== "pdf") return Response.json(data);
  const pdf = generarPdf(lineasInforme(data as Informe));
  return new Response(new Uint8Array(pdf), { headers: { "Content-Type": "application/pdf", "Content-Disposition": `attachment; filename="informe-subvencion-${id}.pdf"` } });
}
