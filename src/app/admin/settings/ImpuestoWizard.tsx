"use client";
import { useEffect, useState } from "react";

type Regla = { id: string; code: string; name: string };
type Cuenta = { id: string; iban: string; name: string };
type Banco = { id: string; code: string; name: string };
type Retro = "prohibited" | "simulation" | "automatic";

const caja = { background: "#fff", border: "1px solid #ddd", borderRadius: 12, padding: 18, marginBottom: 16 } as const;
const campo = { padding: "8px 10px", borderRadius: 8, border: "1px solid #bbb", minWidth: 200 } as const;
const boton = { padding: "8px 16px", borderRadius: 8, border: "1px solid #0b6", background: "#0b6", color: "#fff", cursor: "pointer" } as const;
const botonSec = { padding: "8px 16px", borderRadius: 8, border: "1px solid #bbb", background: "#fff", cursor: "pointer" } as const;
const opcion = (on: boolean) => ({ ...caja, flex: 1, minWidth: 220, marginBottom: 0, cursor: "pointer", borderColor: on ? "#0b6" : "#ddd", background: on ? "#f1fbf6" : "#fff" }) as const;

const PASOS = ["Impuesto", "Cómo se cobra", "Vigencia", "Revisar y crear"];

export function ImpuestoWizard({ tok }: { tok: string }) {
  const cab = { authorization: `Bearer ${tok}`, "content-type": "application/json" };
  const [paso, setPaso] = useState(0);
  const [reglas, setReglas] = useState<Regla[]>([]);
  const [cuentas, setCuentas] = useState<Cuenta[]>([]);
  const [bancos, setBancos] = useState<Banco[]>([]);
  const [existente, setExistente] = useState("");
  const [codigo, setCodigo] = useState("");
  const [nombre, setNombre] = useState("");
  const [tope, setTope] = useState("");
  const [cuenta, setCuenta] = useState("");
  const [metodo, setMetodo] = useState<"percent" | "fixed">("percent");
  const [tipo, setTipo] = useState("");
  const [minimo, setMinimo] = useState("");
  const [maximo, setMaximo] = useState("");
  const [desde, setDesde] = useState(new Date().toISOString().slice(0, 10));
  const [hasta, setHasta] = useState("");
  const [retro, setRetro] = useState<Retro>("prohibited");
  const [banco, setBanco] = useState("");
  const [motivo, setMotivo] = useState("");
  const [msg, setMsg] = useState("");
  const [creada, setCreada] = useState<{ versionId: string } | null>(null);

  useEffect(() => {
    if (!tok) return;
    const get = (ruta: string) => fetch(ruta, { headers: cab }).then((r) => r.json()).catch(() => []);
    get("/api/admin/r/taxrules").then((x) => setReglas(Array.isArray(x) ? x : []));
    get("/api/admin/r/accounts").then((x) => setCuentas(Array.isArray(x) ? x : []));
    get("/api/admin/r/banks").then((x) => setBancos(Array.isArray(x) ? x : []));
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [tok]);

  const num = (s: string) => (s.trim() === "" ? null : Number(s));
  const nueva = existente === "";

  const errores = (): string[] => {
    const e: string[] = [];
    if (nueva) {
      if (!/^[A-Z0-9_]{2,10}$/.test(codigo)) e.push("El código es de 2 a 10 letras mayúsculas, números o guion bajo (ej. IVA, IRM).");
      if (nombre.trim().length < 3) e.push("Escribe el nombre del impuesto.");
      const t = num(tope);
      if (t === null || !Number.isFinite(t) || t < 0 || t > 100) e.push("El límite central debe estar entre 0 y 100 %.");
      if (!cuenta) e.push("Elige la cuenta recaudadora.");
    }
    const r = num(tipo);
    if (r === null || !Number.isFinite(r) || r < 0) e.push(metodo === "percent" ? "Indica el porcentaje." : "Indica el importe fijo.");
    if (metodo === "percent" && r !== null && (r <= 0 || r > (num(tope) ?? 100))) e.push("El porcentaje debe ser mayor que 0 y no superar el límite central.");
    const mn = num(minimo), mx = num(maximo);
    if (mn !== null && mn < 0) e.push("El mínimo no puede ser negativo.");
    if (mn !== null && mx !== null && mx < mn) e.push("El máximo debe ser mayor o igual que el mínimo.");
    if (!desde) e.push("Indica desde cuándo entra en vigor.");
    if (hasta && desde && hasta < desde) e.push("El fin de vigencia no puede ser anterior al inicio.");
    if (motivo.trim().length < 10) e.push("El motivo debe tener al menos 10 caracteres: explica la norma que lo justifica.");
    return e;
  };

  const resumen = () => {
    const r = num(tipo) ?? 0;
    const mn = num(minimo), mx = num(maximo);
    const base = metodo === "percent" ? `el ${r} % de cada operación afectada` : `${r} Pz por cada operación afectada`;
    const ejemplo = metodo === "percent" ? `Ejemplo: una operación de 100 Pz pagaría ${(r).toFixed(2)} Pz.` : `Ejemplo: cada operación pagaría ${r.toFixed(2)} Pz.`;
    const rangos = [mn !== null ? `desde ${mn} Pz` : null, mx !== null ? `hasta ${mx} Pz` : null].filter(Boolean).join(" y ");
    const retroTxt: Record<Retro, string> = { prohibited: "sin retroactividad", simulation: "solo simulación sobre operaciones pasadas", automatic: "aplicación retroactiva automática" };
    return { frase: `Se cobrará ${base}${rangos ? `, ${rangos}` : ""}.`, ejemplo, vigencia: `Desde ${desde}${hasta ? ` hasta ${hasta}` : " sin fin previsto"}, ${retroTxt[retro]}.` };
  };

  const crear = async () => {
    const e = errores();
    if (e.length) return setMsg(e[0]);
    let reglaId = existente;
    if (nueva) {
      const r = await fetch("/api/admin/r/taxrules", { method: "POST", headers: cab, body: JSON.stringify({ code: codigo, name: nombre.trim(), max_rate: Number(tope), collector_account: cuenta }) });
      const j = (await r.json().catch(() => ({}))) as { row?: { id?: string }; error?: string };
      if (!r.ok || !j.row?.id) return setMsg(j.error ?? "No se pudo crear el impuesto");
      reglaId = j.row.id;
    }
    const v = await fetch("/api/admin/r/taxversions", { method: "POST", headers: cab, body: JSON.stringify({ rule_id: reglaId, method: metodo, rate: Number(tipo), min_amount: num(minimo), max_amount: num(maximo), valid_from: desde, valid_to: hasta || null, retro_mode: retro, reason: motivo.trim(), scope_bank: banco || null }) });
    const jv = (await v.json().catch(() => ({}))) as { row?: { id?: string }; error?: string };
    if (!v.ok || !jv.row?.id) return setMsg(jv.error ?? "No se pudo crear la versión");
    setCreada({ versionId: jv.row.id });
    setMsg("Creada como borrador. Para que entre en vigor, la publica otra persona de Fiscal.");
  };

  const publicar = async () => {
    if (!creada) return;
    const r = await fetch(`/api/admin/r/taxversions?id=${creada.versionId}`, { method: "PATCH", headers: cab, body: JSON.stringify({ publish: true }) });
    const j = (await r.json().catch(() => ({}))) as { error?: string };
    setMsg(r.ok ? "Versión publicada: ya está en vigor en la fecha indicada." : (j.error ?? "No se pudo publicar"));
  };

  const pasoOk = (): boolean => {
    if (paso === 0) return !nueva ? true : codigo !== "" && nombre !== "" && cuenta !== "" && tope !== "";
    if (paso === 1) return tipo !== "";
    if (paso === 2) return desde !== "" && motivo.trim().length >= 10;
    return true;
  };

  const r = resumen();

  return (
    <div>
      <div style={{ display: "flex", gap: 8, marginBottom: 16, flexWrap: "wrap" }}>
        {PASOS.map((p, i) => (
          <button key={p} onClick={() => setPaso(i)} style={{ ...botonSec, borderColor: i === paso ? "#0b6" : "#bbb", background: i <= paso ? "#e6f7ef" : "#fff", fontWeight: i === paso ? 700 : 400 }}>
            {i + 1}. {p}
          </button>
        ))}
      </div>

      {paso === 0 && (
        <div style={caja}>
          <h3 style={{ marginTop: 0 }}>¿Qué impuesto es?</h3>
          <label style={{ display: "block", marginBottom: 12 }}>
            Norma existente
            <select value={existente} onChange={(e) => setExistente(e.target.value)} style={{ ...campo, display: "block", marginTop: 4 }}>
              <option value="">— nueva norma —</option>
              {reglas.map((x) => <option key={x.id} value={x.id}>{x.code} · {x.name}</option>)}
            </select>
          </label>
          {nueva && (
            <div style={{ display: "grid", gridTemplateColumns: "repeat(auto-fill, minmax(220px, 1fr))", gap: 12 }}>
              <label>Código<input value={codigo} onChange={(e) => setCodigo(e.target.value.toUpperCase())} placeholder="IVA" style={{ ...campo, display: "block", width: "100%" }} /></label>
              <label>Nombre<input value={nombre} onChange={(e) => setNombre(e.target.value)} placeholder="Impuesto sobre el valor añadido" style={{ ...campo, display: "block", width: "100%" }} /></label>
              <label>Límite central (%)<input type="number" value={tope} onChange={(e) => setTope(e.target.value)} placeholder="21" style={{ ...campo, display: "block", width: "100%" }} /></label>
              <label>Cuenta recaudadora
                <select value={cuenta} onChange={(e) => setCuenta(e.target.value)} style={{ ...campo, display: "block", width: "100%" }}>
                  <option value="">— elige cuenta —</option>
                  {cuentas.map((c) => <option key={c.id} value={c.id}>{c.iban} · {c.name}</option>)}
                </select>
              </label>
            </div>
          )}
        </div>
      )}

      {paso === 1 && (
        <div style={caja}>
          <h3 style={{ marginTop: 0 }}>¿Cómo se cobra?</h3>
          <div style={{ display: "flex", gap: 12, flexWrap: "wrap", marginBottom: 14 }}>
            <div style={opcion(metodo === "percent")} onClick={() => setMetodo("percent")}>
              <b>Porcentaje</b><div style={{ color: "#666", fontSize: 13 }}>Un % sobre el importe de cada operación.</div>
            </div>
            <div style={opcion(metodo === "fixed")} onClick={() => setMetodo("fixed")}>
              <b>Importe fijo</b><div style={{ color: "#666", fontSize: 13 }}>Una cantidad en Pz por cada operación.</div>
            </div>
          </div>
          <div style={{ display: "grid", gridTemplateColumns: "repeat(auto-fill, minmax(200px, 1fr))", gap: 12 }}>
            <label>{metodo === "percent" ? "Porcentaje (%)" : "Importe (Pz)"}<input type="number" step="any" value={tipo} onChange={(e) => setTipo(e.target.value)} style={{ ...campo, display: "block", width: "100%" }} /></label>
            <label>Mínimo (Pz, opcional)<input type="number" step="any" value={minimo} onChange={(e) => setMinimo(e.target.value)} style={{ ...campo, display: "block", width: "100%" }} /></label>
            <label>Máximo (Pz, opcional)<input type="number" step="any" value={maximo} onChange={(e) => setMaximo(e.target.value)} style={{ ...campo, display: "block", width: "100%" }} /></label>
          </div>
          {tipo !== "" && (
            <div style={{ marginTop: 16, padding: 12, borderRadius: 8, background: "#f5f8ff" }}>
              <div><b>Vista previa:</b> {r.frase}</div>
              <div style={{ color: "#555", fontSize: 13 }}>{r.ejemplo}</div>
            </div>
          )}
        </div>
      )}

      {paso === 2 && (
        <div style={caja}>
          <h3 style={{ marginTop: 0 }}>Vigencia y alcance</h3>
          <div style={{ display: "grid", gridTemplateColumns: "repeat(auto-fill, minmax(200px, 1fr))", gap: 12, marginBottom: 14 }}>
            <label>Entra en vigor<input type="date" value={desde} onChange={(e) => setDesde(e.target.value)} style={{ ...campo, display: "block", width: "100%" }} /></label>
            <label>Fin (opcional)<input type="date" value={hasta} onChange={(e) => setHasta(e.target.value)} style={{ ...campo, display: "block", width: "100%" }} /></label>
            <label>Entidad
              <select value={banco} onChange={(e) => setBanco(e.target.value)} style={{ ...campo, display: "block", width: "100%" }}>
                <option value="">Todas las entidades</option>
                {bancos.map((b) => <option key={b.id} value={b.id}>{b.code} · {b.name}</option>)}
              </select>
            </label>
          </div>
          <p><b>Operaciones anteriores a la entrada en vigor</b></p>
          <div style={{ display: "flex", gap: 12, flexWrap: "wrap", marginBottom: 14 }}>
            {(["prohibited", "simulation", "automatic"] as Retro[]).map((x) => {
              const t: Record<Retro, [string, string]> = {
                prohibited: ["No aplicar", "Solo afecta a operaciones desde la entrada en vigor."],
                simulation: ["Solo simular", "Calcula el efecto sobre el pasado sin cobrar nada."],
                automatic: ["Aplicar automáticamente", "Cobra también sobre operaciones pasadas."],
              };
              return (
                <div key={x} style={opcion(retro === x)} onClick={() => setRetro(x)}>
                  <b>{t[x][0]}</b><div style={{ color: "#666", fontSize: 13 }}>{t[x][1]}</div>
                </div>
              );
            })}
          </div>
          <label style={{ display: "block" }}>Motivo y norma que lo justifica (obligatorio)
            <textarea value={motivo} onChange={(e) => setMotivo(e.target.value)} rows={3} style={{ ...campo, display: "block", width: "100%", minWidth: 0, marginTop: 4 }} />
          </label>
        </div>
      )}

      {paso === 3 && (
        <div style={caja}>
          <h3 style={{ marginTop: 0 }}>Revisar antes de crear</h3>
          <div style={{ padding: 14, borderRadius: 10, background: "#f5f8ff", marginBottom: 14 }}>
            <div style={{ fontWeight: 600, fontSize: 16 }}>{nueva ? `${codigo} · ${nombre}` : reglas.find((x) => x.id === existente)?.name ?? "Norma existente"}</div>
            <div style={{ marginTop: 6 }}>{r.frase}</div>
            <div style={{ color: "#555", fontSize: 13 }}>{r.ejemplo}</div>
            <div style={{ color: "#555", fontSize: 13, marginTop: 4 }}>{r.vigencia}</div>
          </div>
          {!creada ? (
            <button style={boton} onClick={crear}>Crear como borrador</button>
          ) : (
            <div>
              <p>Versión creada como borrador. Publicarla exige a otra persona de Fiscal.</p>
              <button style={botonSec} onClick={publicar}>Publicar (aprobador distinto del autor)</button>
            </div>
          )}
        </div>
      )}

      <div style={{ display: "flex", justifyContent: "space-between", gap: 8 }}>
        <button style={botonSec} disabled={paso === 0} onClick={() => setPaso(paso - 1)}>← Anterior</button>
        {paso < 3 && <button style={boton} disabled={!pasoOk()} onClick={() => { const e = errores(); if (paso === 2 && e.length) return setMsg(e[0]); setMsg(""); setPaso(paso + 1); }}>Siguiente →</button>}
      </div>
      {msg && <p role="alert" style={{ marginTop: 12, color: msg.startsWith("Creada") || msg.startsWith("Versión publicada") ? "#0b6" : "#b00" }}>{msg}</p>}
    </div>
  );
}
