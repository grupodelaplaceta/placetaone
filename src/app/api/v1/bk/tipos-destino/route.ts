import { clientFrom } from "@/lib/apikey";
// Tipos de cuenta de destino que ya existen en la plataforma (politicas:gestionar)
const TIPOS = [
  { codigo: "personal", nombre: "Cuentas personales" },
  { codigo: "business", nombre: "Cuentas de empresa (comercios)" },
  { codigo: "shared", nombre: "Cuentas compartidas" },
  { codigo: "junior", nombre: "Cuentas junior" },
  { codigo: "system", nombre: "Cuentas institucionales de sistema" },
];
export async function GET(req: Request) {
  const a = await clientFrom(req, "politicas:gestionar");
  if (a.err) return Response.json({ error: "Denegado" }, { status: a.err });
  return Response.json({ tipos: TIPOS });
}
