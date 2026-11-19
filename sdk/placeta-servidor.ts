// Cliente de SERVIDOR: solo para el backend del banco (Node 18+). Nunca importar desde código de navegador o app.
import { createHmac } from "node:crypto";
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
    const nonce = Array.from(globalThis.crypto.getRandomValues(new Uint8Array(12)), (x) => x.toString(16).padStart(2, "0")).join("");   // único por petición (24 caracteres hex)
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

  // Pasarela de pago: el banco crea el pago; el código de verificación llega por webhook (checkout.codigo)
  crearCheckout(p: { origen: string; client_ref: string; dip: string; iban_pagador: string; iban_destino: string; importe: number; concepto: string; minutos?: number }) {
    return peticion<{ id: string; expira: string; url: string }>(construirUrl(this.base, "/api/v1/bk/checkouts"),
      { method: "POST", headers: this.cabeceras({ "content-type": "application/json" }), body: JSON.stringify(p) }, 0);
  }
  estadoCheckout(id: string) {
    return peticion<any>(construirUrl(this.base, `/api/v1/bk/checkouts/${encodeURIComponent(id)}`), { method: "GET", headers: this.cabeceras() }, 2);
  }

  // Tarjetas: cada operación de cobro necesita una clave de idempotencia (genérala una vez por cobro)
  cobrarTarjeta(p: { card_ref: string; importe: number; iban_comercio: string }, clave: string) {
    return peticion<{ cargo: string; estado: string }>(construirUrl(this.base, "/api/v1/bk/tarjetas/cargos"),
      { method: "POST", headers: this.cabeceras({ "content-type": "application/json", "idempotency-key": clave }), body: JSON.stringify(p) }, 0);
  }
  liquidarCargo(id: string, clave: string) {
    return peticion<{ transaccion: string | null; estado: string }>(construirUrl(this.base, `/api/v1/bk/tarjetas/cargos/${encodeURIComponent(id)}/liquidar`),
      { method: "POST", headers: this.cabeceras({ "idempotency-key": clave }) }, 0);
  }
  liberarCargo(id: string) {
    return peticion<{ estado: string }>(construirUrl(this.base, `/api/v1/bk/tarjetas/cargos/${encodeURIComponent(id)}/liberar`),
      { method: "POST", headers: this.cabeceras() }, 0);
  }

  // Lectura por entidad
  nominas() { return peticion<{ nominas: any[] }>(construirUrl(this.base, "/api/v1/bk/nominas"), { method: "GET", headers: this.cabeceras() }, 2).then((r) => r.nominas); }
  planes() { return peticion<{ planes: any[] }>(construirUrl(this.base, "/api/v1/bk/planes"), { method: "GET", headers: this.cabeceras() }, 2).then((r) => r.planes); }
}
