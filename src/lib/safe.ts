// Garantiza un array aunque la API devuelva otra cosa (objeto de error, null, undefined).
export const arr = <T = any>(x: unknown): T[] => (Array.isArray(x) ? (x as T[]) : []);
