import { staffFrom } from "@/lib/supabase";

type Fila = Record<string, unknown>;
const filas = (x: { data: unknown[] | null }) => (x.data ?? []) as Fila[];

// Convocatorias con su empresa, destino, cuenta de fondos y concesiones resueltas (admin).
export async function GET(req: Request) {
  const s = await staffFrom(req, ["admin"]);
  if (!s) return Response.json({ error: "No autorizado" }, { status: 403 });
  const [cv, ents, emps, accs, grs] = await Promise.all([
    s.db.from("plone27_convocatorias").select("id,entidad,nombre,tipo,importe,desde,hasta,caduca,estado,dirigida_a,empresa_destino,cuenta_fondos,reautoriza_recuperados").order("desde", { ascending: false }),
    s.db.from("plone27_entidades").select("account_id,cip,nombre"),
    s.db.from("plone27_empresas").select("id,nombre,entidad_cip,bank_id"),
    s.db.from("plone27_accounts").select("id,iban,name,bank_id"),
    s.db.from("plone27_grants").select("id,convocatoria,beneficiary_account,granted,paid,estado,caduca"),
  ]);
  const error = [cv, ents, emps, accs, grs].find((x) => x.error);
  if (error) return Response.json({ error: error.error?.message ?? "Error al leer" }, { status: 422 });
  const entPorCuenta = new Map(filas(ents).map((e) => [String(e.account_id), e]));
  const empPorCip = new Map(filas(emps).filter((e) => e.entidad_cip).map((e) => [String(e.entidad_cip), e]));
  const empPorId = new Map(filas(emps).map((e) => [String(e.id), e]));
  const cuentaPorId = new Map(filas(accs).map((a) => [String(a.id), a]));
  const concesionesDe = (id: string) => filas(grs).filter((g) => String(g.convocatoria) === id);

  const convocatorias = filas(cv).map((c) => {
    const id = String(c.id);
    const ent = entPorCuenta.get(String(c.entidad));
    const emp = ent ? empPorCip.get(String(ent.cip)) : undefined;
    const destino = c.empresa_destino ? empPorId.get(String(c.empresa_destino)) : undefined;
    const cs = concesionesDe(id);
    return {
      ...c,
      entidad_nombre: ent ? String(ent.nombre) : null,
      entidad_cip: ent ? String(ent.cip) : null,
      empresa: emp ? { id: String(emp.id), nombre: String(emp.nombre), bank_id: String(emp.bank_id) } : null,
      destino_nombre: destino ? String(destino.nombre) : null,
      cuenta_iban: cuentaPorId.get(String(c.cuenta_fondos))?.iban ?? null,
      concedido: cs.reduce((n, g) => n + Number(g.granted ?? 0), 0),
      pagado: cs.reduce((n, g) => n + Number(g.paid ?? 0), 0),
      concesiones: cs.map((g) => ({
        id: String(g.id),
        beneficiario: cuentaPorId.get(String(g.beneficiary_account))?.iban ?? null,
        granted: Number(g.granted ?? 0), paid: Number(g.paid ?? 0),
        estado: String(g.estado ?? "activa"), caduca: (g.caduca as string | null) ?? null,
      })),
    };
  });
  return Response.json({ convocatorias });
}
