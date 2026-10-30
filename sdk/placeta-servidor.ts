// Cliente de SERVIDOR: solo para el backend del banco (Node 18+). Nunca importar desde código de navegador o app.
import { createHmac, randomBytes } from "node:crypto";
import { peticion, construirUrl, Consulta } from "./placeta-core";

export class PlacetaServidor {
  constructor(private readonly base: string, private readonly clave: string, private readonly secretoFirma: string) {}

  private cabeceras(extra: Record<string, string> = {}): Record<string, string> {
    return { "x-api-key": this.clave, ...extra };
  }

  // Crea una sesión de usuario firmada. Llámalo SOLO después de autenticar a la persona en tu sistema.
  crearSesion(dip: string, o: { minutos?: number; permisos?: string[] } = {}) {
    const cuerpo = JSON.stringify({ dip, minutos: o.minutos ?? 15, permisos: o.permisos });
    const ts = Date.now();
    const nonce = randomBytes(12).toString("base64url");           // único por petición
    const firma = createHmac("sha256", this.secretoFirma).update(`${ts}.${cuerpo}`).digest("hex");
    return peticion<{ token: string; expira: string; permisos: string[] }>(
      construirUrl(this.base, "/api/v1/sessions"),
      { method: "POST", headers: this.cabeceras({ "content-type": "application/json", "x-timestamp": String(ts), "x-nonce": nonce, "x-signature": firma }), body: cuerpo },
      0,
    );
  }

  // Vincula a una persona (DIP) como titular, cotitular o autorizada de una cuenta de tu entidad
  vincularCuenta(dip: string, iban: string, rol: "holder" | "coholder" | "authorized" = "holder") {
    return peticion<{ vinculado: boolean }>(construirUrl(this.base, "/api/v1/bk/link-account"),
      { method: "POST", headers: this.cabeceras({ "content-type": "application/json" }), body: JSON.stringify({ dip, iban, rol }) }, 0);
  }

  // Cuentas de una persona en TU entidad (la respuesta es igual si no existe o no tiene cuentas aquí)
  buscarPorDip(dip: string) {
    return peticion<{ cuentas: any[] }>(construirUrl(this.base, "/api/v1/bk/personas", { dip }), { method: "GET", headers: this.cabeceras() }, 2)
      .then((r) => r.cuentas);
  }

  // Orígenes de navegador (CORS) de tu cliente
  origenes() { return peticion<{ origenes: any[] }>(construirUrl(this.base, "/api/v1/bk/origenes"), { method: "GET", headers: this.cabeceras() }, 2).then((r) => r.origenes); }
  solicitarOrigen(origen: string, entorno: "produccion" | "pruebas" = "produccion") {
    return peticion<{ origen: string; estado: string }>(construirUrl(this.base, "/api/v1/bk/origenes"),
      { method: "POST", headers: this.cabeceras({ "content-type": "application/json" }), body: JSON.stringify({ origen, entorno }) }, 0);
  }
  retirarOrigen(origen: string) {
    return peticion<{ retirado: boolean }>(construirUrl(this.base, "/api/v1/bk/origenes", { origen }), { method: "DELETE", headers: this.cabeceras() }, 0);
  }
}
