"use client";
import { useEffect, useState } from "react";
import { Card, Badge } from "../kit";
import { api } from "@/lib/api";

// Tarifa propietaria de tasas por entidad y posición interbancaria.
type Banco = { id: string; code: string; name: string; nombre_visible?: string | null };
type Tasa = { id: string; ambito: string; client_id: string | null; medio: string | null; tipo: string; valor: number; minimo: number; maximo: number | null; pagador: string; beneficiario: string; activa: boolean };
type Pos = { banco_codigo: string; banco: string; enviado: number; recibido: number; neto: number };

const campo = { padding: 6, borderRadius: 6, border: "1px solid #cbd5e1", marginRight: 6, marginBottom: 6 } as const;

export default function TasasAdmin() {
  const [bancos, setBancos] = useState<Banco[]>([]);
  const [bank, setBank] = useState("");
  const [tasas, setTasas] = useState<Tasa[]>([]);
  const [posicion, setPosicion] = useState<Pos[]>([]);
  const [msg, setMsg] = useState("");
  const [f, setF] = useState<Record<string, string>>({});
  const set = (k: string, v: string) => setF((x) => ({ ...x, [k]: v }));

  useEffect(() => {
    api("/api/admin/pasarela").then((r: { bancos?: Banco[] }) => setBancos(r.bancos ?? [])).catch((e) => setMsg((e as Error).message));
  }, []);

  const cargar = (b: string) => {
    if (!b) return;
    api(`/api/admin/tasas?bank_id=${encodeURIComponent(b)}`).then((r: { tasas?: Tasa[] }) => setTasas(r.tasas ?? [])).catch((e) => setMsg((e as Error).message));
    api(`/api/admin/tasas?bank_id=${encodeURIComponent(b)}&vista=posicion`).then((r: { posicion?: Pos[] }) => setPosicion(r.posicion ?? [])).catch((e) => setMsg((e as Error).message));
  };

  useEffect(() => { setTasas([]); setPosicion([]); cargar(bank); }, [bank]);

  const accion = async (cuerpo: Record<string, unknown>, ok: string) => {
    try { await api("/api/admin/tasas", "POST", { bank_id: bank, ...cuerpo }); setMsg(ok); cargar(bank); }
    catch (e) { setMsg((e as Error).message); }
  };

  return (
    <>
      <h1>Tasas e interbancarias</h1>
      <div style={{ marginBottom: 10 }}>
        <select style={{ ...campo, minWidth: 320 }} value={bank} onChange={(e) => setBank(e.target.value)}>
          <option value="">Elige una entidad…</option>
          {bancos.map((b) => <option key={b.id} value={b.id}>{b.nombre_visible ?? b.name} ({b.code})</option>)}
        </select>
      </div>
      {msg && <p role="status" style={{ background: "#f1f5f9", padding: 8, borderRadius: 6 }}>{msg}</p>}
      {!bank && <p className="muted">Elige una entidad para ver y fijar sus tasas.</p>}

      {bank && (
        <>
          <Card titulo="Tasas de la pasarela (tarifa propietaria)">
            <table style={{ width: "100%", fontSize: 14 }}>
              <thead><tr><th align="left">Ámbito</th><th align="left">Medio</th><th align="left">Tasa</th><th align="left">Paga</th><th align="left">Cobra</th><th align="left">Estado</th><th /></tr></thead>
              <tbody>
                {tasas.map((t) => (
                  <tr key={t.id}>
                    <td>{t.ambito}</td><td>{t.medio ?? "ambos"}</td>
                    <td>{t.tipo === "fijo" ? `${t.valor} Pz` : `${t.valor} %`} (mín {t.minimo}{t.maximo != null ? `, máx ${t.maximo}` : ""})</td>
                    <td>{t.pagador === "comercio" ? "el comercio" : "el banco"}</td>
                    <td>{t.beneficiario === "propietario" ? "el propietario" : "el banco"}</td>
                    <td>{t.activa ? <Badge tono="ok">activa</Badge> : <Badge tono="neutral">desactivada</Badge>}</td>
                    <td>{t.activa && <button className="btn" onClick={() => accion({ accion: "desactivar", id: t.id }, "Tasa desactivada.")}>Desactivar</button>}</td>
                  </tr>
                ))}
              </tbody>
            </table>
            <div style={{ marginTop: 10 }}>
              <select style={campo} value={f.tipo ?? "porcentaje"} onChange={(e) => set("tipo", e.target.value)}>
                <option value="porcentaje">Porcentaje</option><option value="fijo">Importe fijo</option>
              </select>
              <input style={{ ...campo, width: 110 }} type="number" step="0.01" placeholder="Valor" value={f.valor ?? ""} onChange={(e) => set("valor", e.target.value)} />
              <input style={{ ...campo, width: 110 }} type="number" step="0.01" placeholder="Mínimo" value={f.minimo ?? ""} onChange={(e) => set("minimo", e.target.value)} />
              <input style={{ ...campo, width: 110 }} type="number" step="0.01" placeholder="Máximo" value={f.maximo ?? ""} onChange={(e) => set("maximo", e.target.value)} />
              <select style={campo} value={f.medio ?? ""} onChange={(e) => set("medio", e.target.value)}>
                <option value="">Cuenta y tarjeta</option><option value="cuenta">Solo cuenta</option><option value="tarjeta">Solo tarjeta</option>
              </select>
              <select style={campo} value={f.beneficiario ?? "propietario"} onChange={(e) => set("beneficiario", e.target.value)}>
                <option value="propietario">Cobra el propietario</option><option value="banco">Cobra el banco</option>
              </select>
              <select style={campo} value={f.pagador ?? "comercio"} onChange={(e) => set("pagador", e.target.value)}>
                <option value="comercio">Paga el comercio</option><option value="banco">Paga el banco</option>
              </select>
              <button className="btn btn-primary" onClick={() => accion({ accion: "alta", tipo: f.tipo ?? "porcentaje", valor: Number(f.valor ?? 0),
                minimo: Number(f.minimo ?? 0), maximo: f.maximo ? Number(f.maximo) : null, medio: f.medio || null,
                pagador: f.pagador ?? "comercio", beneficiario: f.beneficiario ?? "propietario" }, "Tasa creada.")}>Crear tasa</button>
            </div>
          </Card>

          <Card titulo="Posición interbancaria (últimos 30 días)">
            <table style={{ width: "100%", fontSize: 14 }}>
              <thead><tr><th align="left">Banco</th><th align="right">Enviado</th><th align="right">Recibido</th><th align="right">Neto</th></tr></thead>
              <tbody>
                {posicion.map((p) => (
                  <tr key={p.banco_codigo}>
                    <td>{p.banco} ({p.banco_codigo})</td><td align="right">{p.enviado.toFixed(2)} Pz</td><td align="right">{p.recibido.toFixed(2)} Pz</td>
                    <td align="right"><Badge tono={p.neto >= 0 ? "ok" : "bad"}>{p.neto.toFixed(2)} Pz</Badge></td>
                  </tr>
                ))}
              </tbody>
            </table>
            <p className="muted">Neto negativo: la entidad debe dinero a ese banco. La liquidación se ejecuta fuera de esta pantalla.</p>
          </Card>
        </>
      )}
    </>
  );
}
