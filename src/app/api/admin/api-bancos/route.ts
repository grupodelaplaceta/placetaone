import { staffFrom } from "@/lib/supabase";
// Clientes de la API y sus orígenes de navegador. Solo el personal con rol aprobador puede cambiarlos.
const ORIGEN = /^https?:\/\/[^/\s]+$/;

export async function GET(req: Request) {
  const s = await staffFrom(req, ["aprobador", "auditor"]);
  if (!s) return Response.json({ error: "No autorizado" }, { status: 403 });
  const [clientes, origenes] = await Promise.all([
    s.db.from("plone27_api_clients").select("id,name,scopes,rate_limit,active,created_at").order("created_at", { ascending: false }),
    s.db.from("plone27_client_origins").select("client_id,origin,estado,entorno,solicitado_at"),
  ]);
  if (clientes.error) return Response.json({ error: clientes.error.message }, { status: 500 });
  const sesiones = await s.db.from("plone27_user_sessions").select("client_id").gte("created_at", new Date(Date.now() - 864e5).toISOString());
  const lista = (origenes.data ?? []) as { client_id: string; origin: string; estado: string; entorno: string }[];
  const sesionesPorCliente = new Map<string, number>();
  for (const f of (sesiones.data ?? []) as { client_id: string }[]) sesionesPorCliente.set(f.client_id, (sesionesPorCliente.get(f.client_id) ?? 0) + 1);
  return Response.json({
    clientes: (clientes.data ?? []).map((c: { id: string; scopes?: string[] } & Record<string, unknown>) => {
      const origenesC = lista.filter((o) => o.client_id === c.id);
      return {
        ...c,
        origenes: origenesC,
        integracion: {
          puede_crear_sesiones: (c.scopes ?? []).includes("sesiones:crear"),
          origenes_aprobados: origenesC.filter((o) => o.estado === "aprobado").length,
          origenes_pendientes: origenesC.filter((o) => o.estado === "pendiente").length,
          sesiones_24h: sesionesPorCliente.get(c.id) ?? 0,
        },
      };
    }),
  });
}

// Body: { accion: "alta" | "aprobar" | "rechazar" | "baja", cliente: uuid, origen: "https://dominio" }
export async function POST(req: Request) {
  const s = await staffFrom(req, ["aprobador"]);
  if (!s) return Response.json({ error: "No autorizado" }, { status: 403 });
  const b = await req.json().catch(() => null);
  const origen = String(b?.origen ?? "").trim();
  if (!ORIGEN.test(origen)) return Response.json({ error: "Origen no válido: debe ser https://dominio, sin ruta" }, { status: 400 });
  const cliente = String(b?.cliente ?? "");
  const accion = String(b?.accion ?? "");
  if (!["alta", "aprobar", "rechazar", "baja"].includes(accion)) return Response.json({ error: "Acción no válida" }, { status: 400 });
  let r;
  if (accion === "alta") {
    const pedido = await s.db.rpc("plone27_client_origin_request", { p_client: cliente, p_origin: origen, p_entorno: "produccion" });
    if (pedido.error) return Response.json({ error: pedido.error.message }, { status: 422 });
    r = await s.db.rpc("plone27_client_origin_decide", { p_client: cliente, p_origin: origen, p_decision: "aprobado", p_actor: s.id });
  } else if (accion === "aprobar" || accion === "rechazar") {
    r = await s.db.rpc("plone27_client_origin_decide", { p_client: cliente, p_origin: origen, p_decision: accion === "aprobar" ? "aprobado" : "rechazado", p_actor: s.id });
  } else {
    r = await s.db.rpc("plone27_client_origin_remove", { p_client: cliente, p_origin: origen, p_actor: s.id });
  }
  if (r.error) return Response.json({ error: r.error.message }, { status: 422 });
  return Response.json({ ok: true });
}
