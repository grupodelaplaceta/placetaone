import { clientFrom, hashKey, hexAleatorio } from "@/lib/apikey";
import { SCOPE_KEYS } from "@/lib/scopes";

// Claves de API de la propia entidad (clientes:gestionar). Solo puede conceder permisos de la lista oficial.
export async function GET(req: Request) {
  const a = await clientFrom(req, "clientes:gestionar");
  if (a.err) return Response.json({ error: "Denegado" }, { status: a.err });
  const { data, error } = await a.db.from("plone27_api_clients").select("id,name,scopes,rate_limit,active,created_at").eq("bank_id", a.c.bank_id).order("created_at");
  if (error) return Response.json({ error: "No se pueden listar las claves" }, { status: 422 });
  return Response.json({ clientes: data ?? [] });
}

// Body: { nombre, permisos: ["accounts:read", …], limite?: 60 }. La clave se devuelve una sola vez.
export async function POST(req: Request) {
  const a = await clientFrom(req, "clientes:gestionar");
  if (a.err) return Response.json({ error: "Denegado" }, { status: a.err });
  const b = await req.json().catch(() => null);
  const nombre = String(b?.nombre ?? "").trim();
  const permisos: string[] = Array.isArray(b?.permisos) ? b.permisos.map(String) : [];
  if (nombre.length < 3 || nombre.length > 80) return Response.json({ error: "Nombre entre 3 y 80 caracteres" }, { status: 400 });
  if (permisos.length === 0) return Response.json({ error: "Indica al menos un permiso" }, { status: 400 });
  const desconocidos = permisos.filter((p) => !SCOPE_KEYS.includes(p));
  if (desconocidos.length) return Response.json({ error: `Permisos no válidos: ${desconocidos.join(", ")}` }, { status: 400 });
  const limite = b?.limite == null ? 60 : Number(b.limite);
  if (!(limite >= 1 && limite <= 600)) return Response.json({ error: "Límite entre 1 y 600 peticiones por minuto" }, { status: 400 });
  const clave = "plk_" + hexAleatorio(24);
  const { data, error } = await a.db.from("plone27_api_clients").insert({ bank_id: a.c.bank_id, name: nombre, key_hash: hashKey(clave), scopes: permisos, rate_limit: limite })
    .select("id").single();
  if (error) return Response.json({ error: error.message }, { status: 422 });
  return Response.json({ id: data.id, api_key: clave, aviso: "Guarda la clave ahora: no se vuelve a mostrar." }, { status: 201 });
}
