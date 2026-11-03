"use client";
import { useParams } from "next/navigation";
import { Resource } from "../../Resource";
export default function Cuenta() {
  const { id } = useParams<{ id: string }>(); const f = { account_id: id };
  return (<><h1>Cuenta</h1>
    <Resource res="balances" title="Saldo" filter={f} cols={[{ k: "name", l: "Nombre" }, { k: "kind", l: "Tipo" }, { k: "status", l: "Estado" }, { k: "booked", l: "Contable" }, { k: "reserved", l: "Reservado" }]} />
    <Resource res="ledger" title="Movimientos contables" filter={f} cols={[{ k: "created_at", l: "Fecha" }, { k: "direction", l: "Sentido" }, { k: "amount", l: "Pz" }, { k: "transaction_id", l: "Operación" }]} />
    <Resource res="members" title="Titulares, cotitulares y autorizados" filter={f} cols={[{ k: "user_id", l: "Usuario (UUID)" }, { k: "role", l: "Rol" }]}
      create={[{ k: "user_id", l: "UUID del usuario" }, { k: "role", l: "Rol", t: "select", o: ["holder", "coholder", "authorized"] }]} actions={[{ l: "Quitar", del: true, body: () => ({}) }]} />
    <Resource res="juniors" title="Ficha Junior" filter={f} cols={[{ k: "birth_date", l: "Nacimiento" }, { k: "guardian_user", l: "Tutor (UUID)" }, { k: "per_tx_limit", l: "Límite por operación" }]}
      create={[{ k: "birth_date", l: "Fecha de nacimiento", t: "date" }, { k: "guardian_user", l: "UUID del tutor" }, { k: "per_tx_limit", l: "Límite por operación", t: "number" }]}
      actions={[{ l: "Cambiar límite…", prompt: "Límite por operación (Pz)", body: (r, v) => ({ per_tx_limit: Number(v) }) }]} />
    <Resource res="cards" title="Tarjetas" filter={f} cols={[{ k: "card_ref", l: "Referencia" }, { k: "kind", l: "Tipo" }, { k: "status", l: "Estado" }, { k: "last4", l: "Últimos 4" }]} />
    <Resource res="receipts" title="Recibos fiscales" filter={f} cols={[{ k: "ref", l: "Ref" }, { k: "amount", l: "Importe" }, { k: "paid_amount", l: "Pagado" }, { k: "status", l: "Estado" }, { k: "due_date", l: "Vence" }]} /></>);
}
