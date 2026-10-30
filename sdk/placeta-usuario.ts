// Cliente de USUARIO: web y app. Usa solo el token de sesión (pus_…). Nunca la clave del banco.
import { peticion, construirUrl, Consulta } from "./placeta-core";

type Opciones = { query?: Consulta; body?: unknown; idem?: string };

export class PlacetaUsuario {
  constructor(private readonly base: string, private readonly token: string) {}

  private async req<T>(metodo: string, ruta: string, o: Opciones = {}): Promise<T> {
    const headers: Record<string, string> = { authorization: `Bearer ${this.token}` };
    if (o.body !== undefined) headers["content-type"] = "application/json";
    if (o.idem) headers["idempotency-key"] = o.idem;
    // Las lecturas se reintentan siempre; las escrituras solo si llevan clave de idempotencia.
    const reintentos = metodo === "GET" || o.idem ? 2 : 0;
    return peticion<T>(
      construirUrl(this.base, ruta, o.query),
      { method: metodo, headers, body: o.body !== undefined ? JSON.stringify(o.body) : undefined },
      reintentos,
    );
  }

  // Sesión y datos generales
  me() { return this.req<{ banco: { codigo: string; nombre: string } | null; permisos: string[] }>("GET", "/api/v1/me"); }
  cerrarSesion() { return this.req<{ revocada: boolean }>("DELETE", "/api/v1/sessions"); }
  sesiones() { return this.req<{ sesiones: unknown[] }>("GET", "/api/v1/me/sessions").then((r) => r.sesiones); }
  cerrarOtrasSesiones() { return this.req<{ cerradas: number }>("DELETE", "/api/v1/me/sessions"); }

  // Cuentas
  cuentas() { return this.req<{ cuentas: any[] }>("GET", "/api/v1/me/accounts").then((r) => r.cuentas); }
  cuenta(iban: string) { return this.req<any>("GET", `/api/v1/me/accounts/${encodeURIComponent(iban)}`); }
  abrirCuenta(nombre: string, idem: string) { return this.req<{ cuenta: string }>("POST", "/api/v1/me/accounts", { body: { nombre }, idem }); }
  movimientos(iban: string, q: { antes?: number; limite?: number } = {}) {
    return this.req<{ movimientos: any[]; siguiente: number | null }>("GET", `/api/v1/me/accounts/${encodeURIComponent(iban)}/transactions`, { query: q });
  }
  extracto(iban: string, desde: string, hasta: string) {
    return this.req<any>("GET", `/api/v1/me/accounts/${encodeURIComponent(iban)}/statement`, { query: { desde, hasta } });
  }
  recibos(iban: string) { return this.req<{ recibos: any[] }>("GET", `/api/v1/me/accounts/${encodeURIComponent(iban)}/receipts`).then((r) => r.recibos); }
  certificado(ref: string) { return this.req<any>("GET", `/api/v1/me/receipts/${encodeURIComponent(ref)}/certificate`); }
  tarjetas(iban: string) { return this.req<{ tarjetas: any[] }>("GET", `/api/v1/me/accounts/${encodeURIComponent(iban)}/cards`).then((r) => r.tarjetas); }
  cambiarEstadoTarjeta(ref: string, estado: "active" | "suspended") {
    return this.req<{ estado: string }>("POST", `/api/v1/me/cards/${encodeURIComponent(ref)}`, { body: { estado } });
  }

  // Pagos
  buscarIban(iban: string) { return this.req<{ existe: boolean; entidad?: string; titular?: string }>("GET", "/api/v1/me/lookup", { query: { iban } }); }
  transferir(p: { desde_iban: string; hacia_iban: string; importe: number; concepto?: string }, idem: string) {
    return this.req<{ transaccion: string }>("POST", "/api/v1/me/transfers", { body: p, idem });
  }
  programadas() { return this.req<{ programadas: any[] }>("GET", "/api/v1/me/transfers/scheduled").then((r) => r.programadas); }
  programar(p: { desde_iban: string; hacia_iban: string; importe: number; fecha: string; periodicidad_dias?: number; concepto?: string }, idem: string) {
    return this.req<{ programada: string }>("POST", "/api/v1/me/transfers/scheduled", { body: p, idem });
  }
  cancelarProgramada(id: string) { return this.req<{ cancelada: boolean }>("DELETE", `/api/v1/me/transfers/scheduled/${encodeURIComponent(id)}`); }
  beneficiarios() { return this.req<{ beneficiarios: any[] }>("GET", "/api/v1/me/beneficiaries").then((r) => r.beneficiarios); }
  guardarBeneficiario(alias: string, iban: string) { return this.req<{ beneficiario: string }>("POST", "/api/v1/me/beneficiaries", { body: { alias, iban } }); }
  borrarBeneficiario(id: string) { return this.req<{ borrado: boolean }>("DELETE", `/api/v1/me/beneficiaries/${encodeURIComponent(id)}`); }

  // Avisos, previsión y programas
  notificaciones(q: { soloNuevas?: boolean; limite?: number } = {}) {
    return this.req<{ notificaciones: any[] }>("GET", "/api/v1/me/notifications", { query: { solo_nuevas: q.soloNuevas ? 1 : undefined, limite: q.limite } }).then((r) => r.notificaciones);
  }
  marcarLeidas(ids?: number[]) { return this.req<{ marcadas: number }>("POST", "/api/v1/me/notifications/read", { body: ids ? { ids } : {} }); }
  previsiones(desde: string, hasta: string) { return this.req<{ previsiones: any[] }>("GET", "/api/v1/me/previsiones", { query: { desde, hasta } }).then((r) => r.previsiones); }
  rbu() { return this.req<{ bonos: any[] }>("GET", "/api/v1/me/rbu").then((r) => r.bonos); }
  reclamarRbu(id: string, idem: string) { return this.req<{ transaccion: string }>("POST", `/api/v1/me/rbu/${encodeURIComponent(id)}/claim`, { idem }); }
  planes() { return this.req<{ planes: any[] }>("GET", "/api/v1/me/plans").then((r) => r.planes); }
  solicitudes() { return this.req<{ solicitudes: any[] }>("GET", "/api/v1/me/requests").then((r) => r.solicitudes); }
  solicitar(p: { tipo: "prestamo" | "cuenta"; importe?: number; cuotas?: number; motivo?: string }, idem: string) {
    return this.req<{ solicitud: string }>("POST", "/api/v1/me/requests", { body: p, idem });
  }
}
