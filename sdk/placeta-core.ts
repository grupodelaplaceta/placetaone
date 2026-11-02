// Núcleo común del SDK de Placeta One. Sin dependencias: funciona en navegador, Node 18+, Deno y React Native.

export class PlacetaError extends Error {
  constructor(public readonly status: number, public readonly mensaje: string, public readonly cuerpo?: unknown) {
    super(`${status}: ${mensaje}`);
    this.name = "PlacetaError";
  }
}

export type Consulta = Record<string, string | number | boolean | undefined | null>;

// Ejecuta una petición. Reintenta solo errores transitorios (429 y 5xx) y solo si la operación es segura de repetir.
export async function peticion<T>(url: string, init: RequestInit, reintentos: number): Promise<T> {
  for (let intento = 0; ; intento++) {
    const r = await fetch(url, init);
    const texto = await r.text();
    let cuerpo: any = null;
    try { cuerpo = texto ? JSON.parse(texto) : null; } catch { cuerpo = { error: texto }; }
    if (r.ok) return cuerpo as T;
    const transitorio = r.status === 429 || r.status >= 500;
    if (transitorio && intento < reintentos) {
      await new Promise((res) => setTimeout(res, Math.min(4000, 300 * 2 ** intento)));
      continue;
    }
    throw new PlacetaError(r.status, cuerpo?.error ?? r.statusText, cuerpo);
  }
}

export function construirUrl(base: string, ruta: string, query?: Consulta): string {
  const u = new URL(base.replace(/\/$/, "") + ruta);
  for (const [k, v] of Object.entries(query ?? {})) {
    if (v !== undefined && v !== null && v !== "") u.searchParams.set(k, String(v));
  }
  return u.toString();
}

// Clave única por intento de una acción del usuario. Genérala UNA vez por acción y reutilízala en los reintentos.
export function nuevaClaveIdempotencia(): string {
  return globalThis.crypto.randomUUID();
}
