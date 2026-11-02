// Endpoints autenticados de la API para la comprobación de salud del panel.
// Se leen de la especificación publicada: no pueden quedarse desfasados.
import spec from "../../public/openapi.json";

type Operacion = { security?: unknown[]; "x-permiso"?: string };
const rutas = spec.paths as unknown as Record<string, Record<string, Operacion>>;

export const ENDPOINTS: [string, string, string][] = Object.entries(rutas).flatMap(([ruta, ops]) =>
  Object.entries(ops)
    .filter(([, o]) => (o.security?.length ?? 0) > 0)
    .map(([m, o]): [string, string, string] => [m.toUpperCase(), ruta, o["x-permiso"] ?? ""]));
