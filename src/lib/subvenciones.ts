// Subvenciones: informe de justificación en texto y comprobaciones de pertenencia a una entidad.
export type Informe = {
  subvencion: string; programa: string; tipo: string; beneficiario_iban: string;
  concedido: number; aprobado: number; pagado: number; pendiente_de_pago: number;
  estado: string; caduca: string | null;
  justificaciones: { id: string; factura: string | null; importe: number; estado: string; transferencia: string | null }[];
  reversiones: { importe: number; devuelto: number; deuda: number; motivo: string; fecha: string }[];
  generado: string;
};

// Líneas del informe (sin acentos: el PDF usa Helvetica). Cabe en una página.
export function lineasInforme(i: Informe): string[] {
  const eur = (n: number) => `${Number(n).toFixed(2)} Pz`;
  const l: string[] = [
    "INFORME DE JUSTIFICACION DE SUBVENCION",
    `Programa: ${i.programa} (${i.tipo})`,
    `Beneficiario (IBAN): ${i.beneficiario_iban}`,
    `Estado: ${i.estado}    Caduca: ${i.caduca ?? "sin caducidad"}`,
    "",
    `Concedido: ${eur(i.concedido)}    Aprobado: ${eur(i.aprobado)}`,
    `Pagado: ${eur(i.pagado)}    Pendiente de pago: ${eur(i.pendiente_de_pago)}`,
    "",
    "JUSTIFICACIONES",
  ];
  i.justificaciones.slice(0, 20).forEach((j) => l.push(`- ${j.factura ?? "sin factura"}   ${eur(j.importe)}   ${j.estado}`));
  if (i.justificaciones.length > 20) l.push(`... y ${i.justificaciones.length - 20} mas (ver JSON)`);
  if (i.justificaciones.length === 0) l.push("Ninguna justificacion registrada.");
  l.push("", "ABONOS REVERTIDOS");
  i.reversiones.slice(0, 10).forEach((r) => l.push(`- ${eur(r.importe)}   devuelto ${eur(r.devuelto)}   deuda ${eur(r.deuda)}   ${r.motivo}`));
  if (i.reversiones.length === 0) l.push("Ninguno.");
  l.push("", `Generado: ${i.generado}`);
  return l;
}

// Comprueba que la subvención pertenece a una entidad: su programa se financia desde una cuenta de esa entidad.
// eslint-disable-next-line @typescript-eslint/no-explicit-any
export async function subvencionDeBanco(db: any, bankId: string, grantId: string): Promise<boolean> {
  const g = await db.from("plone27_grants").select("program_id").eq("id", grantId).maybeSingle();
  if (!g.data) return false;
  return programaDeBanco(db, bankId, g.data.program_id as string);
}

// eslint-disable-next-line @typescript-eslint/no-explicit-any
export async function programaDeBanco(db: any, bankId: string, programId: string): Promise<boolean> {
  const p = await db.from("plone27_grant_programs").select("funding_account").eq("id", programId).maybeSingle();
  if (!p.data) return false;
  const a = await db.from("plone27_accounts").select("bank_id").eq("id", p.data.funding_account).maybeSingle();
  return a.data?.bank_id === bankId;
}
