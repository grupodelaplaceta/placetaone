import { clientFrom } from "@/lib/apikey";
import { cipDeEmpresa } from "@/lib/empresas";
import { generarPdf } from "@/lib/pdf";

// Recibos pagados de un periodo (nominas:read). Query: periodo=AAAA-MM, dip? (una persona), formato=json|pdf (por defecto json).
// Con formato=pdf y dip, devuelve el recibo de esa persona en PDF.
export async function GET(req: Request, { params }: { params: Promise<{ id: string }> }) {
  const a = await clientFrom(req, "nominas:read");
  if (a.err) return Response.json({ error: "Denegado" }, { status: a.err });
  const { id } = await params;
  const u = new URL(req.url);
  const periodo = u.searchParams.get("periodo") ?? "";
  const dip = u.searchParams.get("dip");
  const formato = u.searchParams.get("formato") ?? "json";
  const c = await cipDeEmpresa(a.db, a.c.bank_id, id);
  if ("error" in c) return Response.json({ error: c.error }, { status: 422 });
  const { data, error } = await a.db.rpc("plone27_bk_recibos_periodo", { p_bank: a.c.bank_id, p_cip: c.cip, p_periodo: periodo, p_dip: dip });
  if (error) return Response.json({ error: error.message }, { status: 422 });
  const lineas = (data ?? []) as { persona: string; tipo: string; concepto: string; importe: number; tx: string }[];
  if (formato !== "pdf") return Response.json({ periodo, recibos: lineas });
  if (!dip) return Response.json({ error: "Para el PDF indica dip (una persona)" }, { status: 400 });
  if (lineas.length === 0) return Response.json({ error: "No hay pagos de esa persona en el periodo" }, { status: 404 });
  const total = lineas.reduce((s, l) => s + Number(l.importe), 0);
  const cuerpo = [
    "RECIBO DE NOMINA",
    `Entidad: ${c.cip}`,
    `Periodo: ${periodo}`,
    `Persona: ${dip}`,
    "",
    ...lineas.map((l) => `${l.tipo === "salario" ? "Salario" : "Complemento"} - ${l.concepto}: ${Number(l.importe).toFixed(2)} Pz`),
    "",
    `TOTAL: ${total.toFixed(2)} Pz`,
    "",
    ...lineas.map((l) => `Transferencia: ${l.tx}`),
  ];
  const pdf = generarPdf(cuerpo);
  return new Response(new Uint8Array(pdf), {
    headers: { "Content-Type": "application/pdf", "Content-Disposition": `attachment; filename="recibo-${periodo}-${dip}.pdf"` },
  });
}
