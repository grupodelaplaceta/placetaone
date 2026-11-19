import { clientFrom, hashKey, hexAleatorio } from "@/lib/apikey";
import { textoContrato } from "@/lib/contrato-empresa";

// Dar de alta la pasarela de una empresa: crea su cliente de API y genera su contrato (empresas:gestionar).
// La clave se devuelve una sola vez. Body: { dip_actor, nombre_cliente?, scopes? }
const SCOPES_EMPRESA = ["checkout:crear", "branding:gestionar", "webhooks:gestionar", "origenes:gestionar", "accounts:read"];
const BASE = process.env.PLACETA_PUBLIC_URL ?? "https://placetaone.vercel.app";

export async function POST(req: Request, { params }: { params: Promise<{ id: string }> }) {
  const a = await clientFrom(req, "empresas:gestionar");
  if (a.err) return Response.json({ error: "Denegado" }, { status: a.err });
  const { id } = await params;
  const b = await req.json().catch(() => null);
  const actor = await a.db.rpc("plone27_persona", { p_dip: String(b?.dip_actor ?? "") });
  if (actor.error) return Response.json({ error: actor.error.message }, { status: 422 });
  const scopes = Array.isArray(b?.scopes) ? b.scopes.map(String) : SCOPES_EMPRESA;
  const nombreCliente = String(b?.nombre_cliente ?? "Pasarela de empresa");
  const clave = "plk_" + hexAleatorio(24);
  const alta = await a.db.rpc("plone27_empresa_pasarela_registrar", { p_bank: a.c.bank_id, p_empresa: id, p_nombre: nombreCliente,
    p_key_hash: hashKey(clave), p_scopes: scopes, p_actor: actor.data });
  if (alta.error) return Response.json({ error: alta.error.message }, { status: 422 });
  const empresa = await a.db.from("plone27_empresas").select("nombre,identificador_fiscal").eq("id", id).maybeSingle();
  const banco = await a.db.from("plone27_banks").select("name").eq("id", a.c.bank_id).maybeSingle();
  const actual = await a.db.rpc("plone27_empresa_contrato_actual", { p_bank: a.c.bank_id, p_empresa: id });
  const version = Number(actual.data?.version ?? 0) + 1;
  const texto = textoContrato({ banco: banco.data?.name ?? "", empresa: empresa.data?.nombre ?? "", fiscal: empresa.data?.identificador_fiscal ?? "",
    version, scopes, base: BASE, clienteNombre: nombreCliente });
  const guardado = await a.db.rpc("plone27_empresa_contrato_guardar", { p_bank: a.c.bank_id, p_empresa: id, p_texto: texto });
  if (guardado.error) return Response.json({ error: guardado.error.message }, { status: 422 });
  return Response.json({ client_id: alta.data, clave, aviso: "Guarda la clave ahora: no se vuelve a mostrar.",
    contrato: { version: guardado.data, texto } }, { status: 201 });
}
