// Formato de fechas para la interfaz. Vacíos, no válidos y anteriores a 2000 se muestran como "—"
// (un valor así es un dato erróneo, no una fecha). 2999 significa "sin caducidad".
const MINIMO = 2000;
const SIN_CADUCIDAD = 2999;

function aFecha(v: unknown): Date | null {
  if (v === null || v === undefined || v === "") return null;
  if (typeof v === "string" && /^\d{4}-\d{2}-\d{2}$/.test(v)) {
    const [y, m, d] = v.split("-").map(Number);
    return new Date(y, m - 1, d, 12);
  }
  const d = v instanceof Date ? v : new Date(String(v));
  return Number.isNaN(d.getTime()) ? null : d;
}

export function fechaSolo(v: unknown): string {
  const d = aFecha(v);
  if (!d) return "—";
  if (d.getFullYear() >= SIN_CADUCIDAD) return "sin caducidad";
  if (d.getFullYear() < MINIMO) return "—";
  return d.toLocaleDateString("es-ES", { day: "2-digit", month: "2-digit", year: "numeric" });
}

export function fechaHora(v: unknown): string {
  const d = aFecha(v);
  if (!d) return "—";
  if (d.getFullYear() >= SIN_CADUCIDAD) return "sin caducidad";
  if (d.getFullYear() < MINIMO) return "—";
  return d.toLocaleString("es-ES", { day: "2-digit", month: "2-digit", year: "numeric", hour: "2-digit", minute: "2-digit" });
}
