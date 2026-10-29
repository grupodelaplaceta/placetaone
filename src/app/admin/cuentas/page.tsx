"use client";
import { Resource } from "../Resource";
export default function Cuentas() {
  return (<><h1>Cuentas y saldos</h1><Resource res="balances" title="Todas las cuentas" cols={[{ k: "name", l: "Nombre" }, { k: "kind", l: "Tipo" }, { k: "status", l: "Estado" }, { k: "booked", l: "Saldo contable" }, { k: "reserved", l: "Reservado" }]} href={r => `/admin/cuentas/${r.account_id}`} /></>);
}
