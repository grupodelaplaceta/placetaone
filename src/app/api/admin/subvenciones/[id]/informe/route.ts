import { staffFrom } from "@/lib/supabase";
import { generarPdf } from "@/lib/pdf";
import { lineasInforme, type Informe } from "@/lib/subvenciones";

// Informe de justificación (admin). Query: formato=json (defecto) | pdf
export async function GET(req: Request, { params }: { params: Promise<{ id: string }> }) {
  const s = await staffFrom(req, ["admin"]);
  if (!s) return Response.json({ error: "No autorizado" }, { status: 403 });
  const { id } = await params;
  const formato = new URL(req.url).searchParams.get("formato") ?? "json";
  const { data, error } = await s.db.rpc("plone27_grant_informe", { p_grant: id });
  if (error) return Response.json({ error: error.message }, { status: 422 });
  if (formato !== "pdf") return Response.json(data);
  const pdf = generarPdf(lineasInforme(data as Informe));
  return new Response(new Uint8Array(pdf), { headers: { "Content-Type": "application/pdf", "Content-Disposition": `attachment; filename="informe-subvencion-${id}.pdf"` } });
}
