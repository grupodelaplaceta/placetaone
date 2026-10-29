"use client";
import { useEffect, useState } from "react";
import Link from "next/link";
import { sb, initSb } from "@/lib/browser";
const NAV: [string, string][] = [["/admin", "Panel"], ["/admin/bancos", "Bancos"], ["/admin/cuentas", "Cuentas"], ["/admin/productos", "Productos"], ["/admin/operaciones", "Operaciones"], ["/admin/financiacion", "Financiación"], ["/admin/fiscal", "Fiscalidad"], ["/admin/registros", "Registros"], ["/admin/personal", "Personal"], ["/admin/api", "API"], ["/admin/numeracion", "Numeración"], ["/admin/procesos", "Procesos"], ["/admin/settings", "Configuración"], ["/admin/console", "Consola"]];
export default function AdminLayout({ children }: { children: React.ReactNode }) {
  const [state, setState] = useState<"load" | "out" | "in" | "err">("load"); const [msg, setMsg] = useState("");
  useEffect(() => { let off = () => {};
    initSb().then(() => { sb().auth.getSession().then(({ data }) => setState(data.session ? "in" : "out")); const { data: l } = sb().auth.onAuthStateChange((_e, s) => setState(s ? "in" : "out")); off = () => l.subscription.unsubscribe(); })
      .catch(e => { setMsg(e.message); setState("err"); });
    return () => off(); }, []);
  const login = async (e: React.FormEvent<HTMLFormElement>) => { e.preventDefault(); const f = new FormData(e.currentTarget);
    const { error } = await sb().auth.signInWithPassword({ email: String(f.get("e")), password: String(f.get("p")) }); if (error) setMsg(error.message); };
  if (state === "load") return null;
  if (state === "err") return (<main style={{ maxWidth: 560, margin: "80px auto", padding: 24 }}><h1>Configuración incompleta</h1><p role="alert" style={{ color: "#a33" }}>{msg}</p><p>Añádelas en Vercel → Settings → Environment Variables y haz un Redeploy. Comprueba qué ve el servidor en <a href="/api/public-config">/api/public-config</a>.</p></main>);
  if (state === "out") return (<main style={{ maxWidth: 360, margin: "80px auto", padding: 24 }}><h1>Placeta One</h1>{msg && <p role="alert" style={{ color: "#a33" }}>{msg}</p>}
    <form onSubmit={login} style={{ display: "grid", gap: 8 }}><input name="e" type="email" placeholder="Email" required /><input name="p" type="password" placeholder="Contraseña" required /><button>Entrar</button></form></main>);
  return (<div style={{ display: "flex", minHeight: "100vh" }}><nav style={{ width: 190, background: "#1b1b18", padding: 16, display: "grid", alignContent: "start", gap: 10 }}>
    <b style={{ color: "#fff", fontSize: 18 }}>Placeta One</b>{NAV.map(([h, l]) => <Link key={h} href={h} style={{ color: "#ddd", textDecoration: "none" }}>{l}</Link>)}
    <button onClick={() => sb().auth.signOut()} style={{ marginTop: 24 }}>Salir</button></nav><div style={{ flex: 1, padding: 24, maxWidth: 1100 }}>{children}</div></div>);
}
