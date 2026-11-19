import { hashKey, hexAleatorio } from "./apikey";
import { textoContrato } from "./contrato-empresa";

// Operaciones de empresas compartidas por la API del banco y el panel de administración.
export const SCOPES_EMPRESA = ["checkout:crear", "branding:gestionar", "webhooks:gestionar", "origenes:gestionar", "accounts:read"];
const BASE = process.env.PLACETA_PUBLIC_URL ?? "https://placetaone.vercel.app";

// eslint-disable-next-line @typescript-eslint/no-explicit-any
type Db = any;

export async function personaPorDip(db: Db, dip: string): Promise<string> {
  const r = await db.rpc("plone27_persona", { p_dip: dip });
  if (r.error) throw new Error(r.error.message);
  return r.data as string;
}

// Alta de la pasarela de una empresa: cliente de API, clave (una sola vez) y contrato versionado
export async function altaPasarelaEmpresa(db: Db, bankId: string, empresaId: string, actorId: string, nombre: string, scopes: string[]) {
  const clave = "plk_" + hexAleatorio(24);
  const alta = await db.rpc("plone27_empresa_pasarela_registrar", { p_bank: bankId, p_empresa: empresaId, p_nombre: nombre,
    p_key_hash: hashKey(clave), p_scopes: scopes, p_actor: actorId });
  if (alta.error) throw new Error(alta.error.message);
  const empresa = await db.from("plone27_empresas").select("nombre,identificador_fiscal").eq("id", empresaId).maybeSingle();
  const banco = await db.from("plone27_banks").select("name").eq("id", bankId).maybeSingle();
  const actual = await db.rpc("plone27_empresa_contrato_actual", { p_bank: bankId, p_empresa: empresaId });
  const version = Number(actual.data?.version ?? 0) + 1;
  const texto = textoContrato({ banco: banco.data?.name ?? "", empresa: empresa.data?.nombre ?? "", fiscal: empresa.data?.identificador_fiscal ?? "",
    version, scopes, base: BASE, clienteNombre: nombre });
  const guardado = await db.rpc("plone27_empresa_contrato_guardar", { p_bank: bankId, p_empresa: empresaId, p_texto: texto });
  if (guardado.error) throw new Error(guardado.error.message);
  return { client_id: alta.data as string, clave, contrato: { version: guardado.data as number, texto } };
}

// Rotación de la clave de la pasarela de una empresa: la anterior deja de valer
export async function rotarClaveEmpresa(db: Db, bankId: string, empresaId: string, actorId: string) {
  const clave = "plk_" + hexAleatorio(24);
  const r = await db.rpc("plone27_empresa_pasarela_rotar", { p_bank: bankId, p_empresa: empresaId, p_key_hash: hashKey(clave), p_actor: actorId });
  if (r.error) throw new Error(r.error.message);
  return { client_id: r.data as string, clave };
}

// CIP (entidad institucional) de una empresa de la entidad del banco. Error si la empresa aún no tiene entidad.
export async function cipDeEmpresa(db: Db, bankId: string, empresaId: string): Promise<{ cip: string } | { error: string }> {
  const r = await db.from("plone27_empresas").select("entidad_cip").eq("id", empresaId).eq("bank_id", bankId).maybeSingle();
  if (r.error) return { error: r.error.message };
  if (!r.data) return { error: "Empresa no encontrada en tu entidad" };
  if (!r.data.entidad_cip) return { error: "La empresa todavía no tiene entidad institucional: añade una cuenta de empresa" };
  return { cip: r.data.entidad_cip as string };
}
