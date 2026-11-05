"use client";
import { useEffect, useState } from "react";
import { Card, Badge } from "../kit";
import { api } from "@/lib/api";

// Categorías de comercio. Las asigna Placeta: las usan las reglas de RBU y de subvenciones para decidir dónde se puede gastar.
type Cat = { codigo: string; nombre: string; activa: boolean };
type Com = { iban: string; nombre: string; categoria: string | null; banco: string };
const campo = { padding: 6, borderRadius: 6, border: "1px solid #cbd5e1", marginRight: 6, marginBottom: 6 } as const;

export default function ComerciosAdmin() {
  const [cats, setCats] = useState<Cat[]>([]);
  const [coms, setComs] = useState<Com[]>([]);
  const [msg, setMsg] = useState("");
  const [f, setF] = useState<Record<string, string>>({});
  const set = (k: string, v: string) => setF((x) => ({ ...x, [k]: v }));
  const cargar = () => api("/api/admin/comercios").then((r: { categorias?: Cat[]; comercios?: Com[] }) => { setCats(r.categorias ?? []); setComs(r.comercios ?? []); }).catch((e) => setMsg((e as Error).message));
  useEffect(() => { cargar(); }, []);
  const accion = async (cuerpo: Record<string, unknown>, ok: string) => {
    try { await api("/api/admin/comercios", "POST", cuerpo); setMsg(ok); cargar(); } catch (e) { setMsg((e as Error).message); }
  };
  return (
    <>
      <h1>Comercios y categorías</h1>
      {msg && <p role="status" style={{ background: "#f1f5f9", padding: 8, borderRadius: 6 }}>{msg}</p>}
      <Card titulo="Cómo se usan las categorías">
        <p>Cada cuenta de comercio (empresa) puede tener una categoría. Las reglas de uso de cada banco (RBU y programas de subvención) pueden limitar el gasto a comercios de ciertas categorías o a comercios concretos. Si un comercio no tiene categoría, las reglas que filtran por categoría no le permiten cobrar.</p>
      </Card>
      <Card titulo="Categorías">
        <table style={{ width: "100%", fontSize: 14 }}>
          <thead><tr><th align="left">Código</th><th align="left">Nombre</th><th align="left">Estado</th></tr></thead>
          <tbody>{cats.map((c) => <tr key={c.codigo}><td className="mono">{c.codigo}</td><td>{c.nombre}</td><td>{c.activa ? <Badge tono="ok">activa</Badge> : <Badge tono="neutral">inactiva</Badge>}</td></tr>)}</tbody>
        </table>
        <input style={campo} placeholder="Código (a-z y _, 3 a 30)" value={f.cod ?? ""} onChange={(e) => set("cod", e.target.value)} />
        <input style={campo} placeholder="Nombre" value={f.nom ?? ""} onChange={(e) => set("nom", e.target.value)} />
        <button className="btn btn-primary" onClick={() => accion({ accion: "categoria_set", codigo: f.cod ?? "", nombre: f.nom ?? "", activa: true }, "Categoría guardada.")}>Guardar categoría</button>
      </Card>
      <Card titulo="Comercios (cuentas de empresa)">
        <table style={{ width: "100%", fontSize: 14 }}>
          <thead><tr><th align="left">Nombre</th><th align="left">Cuenta</th><th align="left">Banco</th><th align="left">Categoría</th><th /></tr></thead>
          <tbody>{coms.map((c) => (
            <tr key={c.iban}>
              <td>{c.nombre}</td><td className="mono">{c.iban}</td><td>{c.banco}</td><td>{c.categoria ?? <Badge tono="bad">sin categoría</Badge>}</td>
              <td><select style={campo} defaultValue={c.categoria ?? ""} onChange={(e) => accion({ accion: "comercio_categoria", iban: c.iban, categoria: e.target.value || null }, "Categoría asignada.")}>
                <option value="">— sin categoría —</option>{cats.filter((x) => x.activa).map((x) => <option key={x.codigo} value={x.codigo}>{x.nombre}</option>)}
              </select></td>
            </tr>))}</tbody>
        </table>
      </Card>
    </>
  );
}
