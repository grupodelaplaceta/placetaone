"use client";
import { useEffect, useMemo, useState } from "react";
import { sb } from "@/lib/browser";
import { ImpuestoWizard } from "./ImpuestoWizard";

type S = { key: string; category: string; description: string; vtype: string; allowed: string[] | null; min_v: number | null; max_v: number | null; value: unknown; sensitive: boolean; bank_overridable: boolean; version: number };
type C = { id: string; key: string; bank_id: string | null; new_value: unknown; old_value: unknown; reason: string };
type Datos = { settings: S[]; pending: C[]; banks: { id: string; code: string; name: string }[] };

const CATEGORIAS: Record<string, string> = { justicia: "Sanciones", joven: "Placeta Joven", aprobaciones: "Aprobaciones", bienestar: "RBU y bienestar", cobros: "Cobros", cuentas: "Cuentas", finanzas: "Finanzas", fiscalidad: "Fiscalidad", integraciones: "Integraciones", junior: "Cuentas Junior", laboral: "Laboral", normas: "Normas y topes", tasas: "Tasas" };
const caja = { background: "#fff", border: "1px solid #ddd", borderRadius: 12, padding: 18, marginBottom: 16 } as const;
const campo = { padding: "6px 10px", borderRadius: 8, border: "1px solid #bbb" } as const;
const boton = { padding: "6px 14px", borderRadius: 8, border: "1px solid #0b6", background: "#0b6", color: "#fff", cursor: "pointer" } as const;
const botonSec = { padding: "6px 14px", borderRadius: 8, border: "1px solid #bbb", background: "#fff", cursor: "pointer" } as const;

const formatea = (v: unknown): string => {
  if (typeof v === "boolean") return v ? "Sí" : "No";
  if (v === null || v === undefined || v === "") return "—";
  return typeof v === "string" ? v : JSON.stringify(v);
};

function Ajuste({ s, tok, bank, avisar, recargar }: { s: S; tok: string; bank: string; avisar: (m: string) => void; recargar: () => void }) {
  const [v, setV] = useState<unknown>(s.value);
  const [motivo, setMotivo] = useState("");
  const [enviando, setEnviando] = useState(false);
  const cambiado = formatea(v) !== formatea(s.value);
  // Como en la versión anterior: un ajuste que no admite cambio por entidad solo se cambia en el ámbito global
  const bloqueado = !!bank && !s.bank_overridable;

  const proponer = async () => {
    if (bloqueado) return avisar("Este ajuste solo se cambia en el ámbito global.");
    if (motivo.trim().length < 5) return avisar("Escribe un motivo de al menos 5 caracteres.");
    const valor = s.vtype === "number" ? Number(v) : s.vtype === "boolean" ? Boolean(v) : v;
    if (s.vtype === "number" && !Number.isFinite(valor as number)) return avisar("Valor numérico no válido.");
    setEnviando(true);
    const r = await fetch("/api/rpc/plone27_setting_propose", { method: "POST", headers: { authorization: `Bearer ${tok}`, "content-type": "application/json" }, body: JSON.stringify({ p_key: s.key, p_value: valor, p_bank: bank || null, p_reason: motivo.trim() }) });
    const j = (await r.json().catch(() => ({}))) as { error?: string };
    setEnviando(false);
    if (!r.ok) return avisar(j.error ?? "No se pudo proponer el cambio.");
    setMotivo(""); setV(s.value); avisar("Cambio propuesto: lo aprueba otra persona."); recargar();
  };

  let control;
  if (s.vtype === "boolean") control = <button role="switch" disabled={bloqueado} aria-checked={Boolean(v)} onClick={() => setV(!v)} style={{ ...botonSec, minWidth: 110, background: v ? "#e6f7ef" : "#f5f5f5" }}>{v ? "Activado" : "Desactivado"}</button>;
  else if (s.allowed) control = <select disabled={bloqueado} value={String(v ?? "")} onChange={(e) => setV(e.target.value)} style={campo}>{s.allowed.map((o) => <option key={o} value={o}>{o}</option>)}</select>;
  else if (s.vtype === "number") control = <input disabled={bloqueado} type="number" step="any" value={v === null || v === undefined ? "" : String(v)} min={s.min_v ?? undefined} max={s.max_v ?? undefined} onChange={(e) => setV(e.target.value === "" ? "" : Number(e.target.value))} style={{ ...campo, width: 130 }} />;
  else control = <input disabled={bloqueado} value={String(v ?? "")} onChange={(e) => setV(e.target.value)} style={{ ...campo, width: 220 }} />;

  return (
    <div style={{ borderTop: "1px solid #eee", padding: "12px 0", display: "grid", gridTemplateColumns: "1fr auto", gap: 12, alignItems: "center" }}>
      <div>
        <div style={{ fontWeight: 600 }}>
          {s.description}
          {s.sensitive && <span title="Requiere la aprobación de otra persona" style={{ marginLeft: 8, fontSize: 12, color: "#8a5a00", background: "#fff4d6", padding: "2px 8px", borderRadius: 10 }}>🔒 2ª persona</span>}
        </div>
        <div style={{ fontSize: 12, color: "#777", fontFamily: "monospace" }}>
          {s.key} · actual: <b>{formatea(s.value)}</b>{s.min_v !== null && <> · rango {s.min_v}–{s.max_v}</>}
        </div>
        {bloqueado && <div style={{ fontSize: 12, color: "#8a5a00" }}>Solo se cambia en el ámbito global</div>}
        {cambiado && (
          <div style={{ marginTop: 8, display: "flex", gap: 8, flexWrap: "wrap" }}>
            <input placeholder="Motivo (obligatorio)" value={motivo} onChange={(e) => setMotivo(e.target.value)} style={{ ...campo, minWidth: 260 }} />
            <button style={boton} disabled={enviando} onClick={proponer}>Proponer cambio</button>
            <button style={botonSec} onClick={() => setV(s.value)}>Descartar</button>
          </div>
        )}
      </div>
      <div>{control}</div>
    </div>
  );
}

export default function Settings() {
  const [tok, setTok] = useState("");
  const [d, setD] = useState<Datos | null>(null);
  const [msg, setMsg] = useState("");
  const [bank, setBank] = useState("");
  const [busca, setBusca] = useState("");
  const [cat, setCat] = useState("todas");
  const [pestana, setPestana] = useState<"ajustes" | "impuesto">("ajustes");

  const cargar = async (t: string) => {
    const r = await fetch("/api/admin/settings", { headers: { authorization: `Bearer ${t}` } });
    if (r.ok) setD((await r.json()) as Datos);
    else setMsg(((await r.json().catch(() => ({}))) as { error?: string }).error ?? "No autorizado");
  };

  useEffect(() => {
    sb().auth.getSession().then(({ data }: { data: { session: { access_token: string } | null } }) => {
      if (data.session) { setTok(data.session.access_token); cargar(data.session.access_token); }
    });
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, []);

  const login = async (e: React.FormEvent<HTMLFormElement>) => {
    e.preventDefault();
    const f = new FormData(e.currentTarget);
    const { data, error } = await sb().auth.signInWithPassword({ email: String(f.get("e")), password: String(f.get("p")) });
    if (error || !data.session) return setMsg(error?.message ?? "Error al entrar");
    setTok(data.session.access_token); cargar(data.session.access_token);
  };

  const decidir = async (id: string, aprobar: boolean) => {
    const r = await fetch("/api/rpc/plone27_setting_approve", { method: "POST", headers: { authorization: `Bearer ${tok}`, "content-type": "application/json" }, body: JSON.stringify({ p_change: id, p_approve: aprobar }) });
    const j = (await r.json().catch(() => ({}))) as { error?: string };
    setMsg(r.ok ? (aprobar ? "Cambio aprobado." : "Cambio rechazado.") : (j.error ?? "Error"));
    if (r.ok) cargar(tok);
  };

  const categorias = useMemo(() => {
    const m = new Map<string, number>();
    (d?.settings ?? []).forEach((s) => m.set(s.category, (m.get(s.category) ?? 0) + 1));
    return Array.from(m.entries());
  }, [d]);

  const visibles = (d?.settings ?? []).filter((s) =>
    (cat === "todas" || s.category === cat) &&
    (!busca || (s.key + " " + s.description).toLowerCase().includes(busca.toLowerCase())));

  const grupos = Array.from(new Set(visibles.map((s) => s.category)));

  return (
    <main style={{ maxWidth: 1000, margin: "0 auto", padding: 24 }}>
      <h1>Configuración</h1>
      {msg && <p role="alert" style={{ color: "#333" }}>{msg}</p>}
      {!d ? (
        <form onSubmit={login} style={caja}>
          <input name="e" type="email" placeholder="Email" required style={campo} />{" "}
          <input name="p" type="password" placeholder="Contraseña" required style={campo} />{" "}
          <button style={boton}>Entrar</button>
        </form>
      ) : (
        <>
          <div style={{ display: "flex", gap: 8, marginBottom: 16 }}>
            <button style={{ ...botonSec, fontWeight: pestana === "ajustes" ? 700 : 400 }} onClick={() => setPestana("ajustes")}>Ajustes</button>
            <button style={{ ...botonSec, fontWeight: pestana === "impuesto" ? 700 : 400 }} onClick={() => setPestana("impuesto")}>Nuevo impuesto</button>
          </div>

          {pestana === "impuesto" ? <ImpuestoWizard tok={tok} /> : (
            <>
              {d.pending.length > 0 && (
                <section style={{ ...caja, borderColor: "#f0c060", background: "#fffaf0" }}>
                  <h2 style={{ marginTop: 0, fontSize: 18 }}>Pendientes de aprobación ({d.pending.length})</h2>
                  {d.pending.map((c) => (
                    <div key={c.id} style={{ display: "flex", justifyContent: "space-between", gap: 12, flexWrap: "wrap", padding: "8px 0", borderTop: "1px solid #f3e4c0" }}>
                      <div>
                        <b>{c.key}</b>: <span style={{ color: "#888" }}>{formatea(c.old_value)}</span> → <b>{formatea(c.new_value)}</b>
                        <div style={{ fontSize: 13, color: "#666" }}>{c.reason}</div>
                      </div>
                      <div style={{ display: "flex", gap: 8 }}>
                        <button style={boton} onClick={() => decidir(c.id, true)}>Aprobar</button>
                        <button style={botonSec} onClick={() => decidir(c.id, false)}>Rechazar</button>
                      </div>
                    </div>
                  ))}
                </section>
              )}

              <section style={caja}>
                <div style={{ display: "flex", gap: 12, flexWrap: "wrap", alignItems: "center", marginBottom: 12 }}>
                  <input placeholder="Buscar ajuste…" value={busca} onChange={(e) => setBusca(e.target.value)} style={{ ...campo, minWidth: 240 }} />
                  <label>Ámbito:{" "}
                    <select value={bank} onChange={(e) => setBank(e.target.value)} style={campo}>
                      <option value="">Global</option>
                      {d.banks.map((b) => <option key={b.id} value={b.id}>{b.code} · {b.name}</option>)}
                    </select>
                  </label>
                </div>
                <div style={{ display: "flex", gap: 6, flexWrap: "wrap" }}>
                  <button onClick={() => setCat("todas")} style={{ ...botonSec, background: cat === "todas" ? "#e6f7ef" : "#fff" }}>Todas ({d.settings.length})</button>
                  {categorias.map(([c, n]) => (
                    <button key={c} onClick={() => setCat(c)} style={{ ...botonSec, background: cat === c ? "#e6f7ef" : "#fff" }}>{CATEGORIAS[c] ?? c} ({n})</button>
                  ))}
                </div>
              </section>

              {grupos.length === 0 && <p style={{ color: "#777" }}>Ningún ajuste coincide con la búsqueda.</p>}
              {grupos.map((g) => (
                <section key={g} style={caja}>
                  <h2 style={{ marginTop: 0, fontSize: 18 }}>{CATEGORIAS[g] ?? g}</h2>
                  {visibles.filter((s) => s.category === g).map((s) => (
                    <Ajuste key={s.key} s={s} tok={tok} bank={bank} avisar={setMsg} recargar={() => cargar(tok)} />
                  ))}
                </section>
              ))}
            </>
          )}
        </>
      )}
    </main>
  );
}
