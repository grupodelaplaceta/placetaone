"use client";
import "./admin.css";
import { useEffect, useState } from "react";
import Link from "next/link";
import { usePathname } from "next/navigation";
import { sb, initSb } from "@/lib/browser";
import { DialogHost } from "./ui";

// Menú agrupado por área. Cada página del panel aparece una sola vez.
const GRUPOS: { titulo: string; items: [string, string][] }[] = [
  { titulo: "Principal", items: [["/admin", "Panel"], ["/admin/previsiones", "Previsiones"], ["/admin/estado", "Estado"]] },
  { titulo: "Clientes y cuentas", items: [["/admin/clientes", "Clientes"], ["/admin/cuentas", "Cuentas"], ["/admin/operaciones", "Operaciones"], ["/admin/registros", "Registros"], ["/admin/disputas", "Disputas"]] },
  { titulo: "Productos", items: [["/admin/productos", "Productos"], ["/admin/financiacion", "Financiación"], ["/admin/normas", "Normas"]] },
  { titulo: "Fiscalidad", items: [["/admin/infraestructura", "Infraestructura"], ["/admin/fiscal", "Fiscalidad"], ["/admin/iva", "IVA"], ["/admin/destinos", "Destinos"]] },
  { titulo: "Entidades", items: [["/admin/bancos", "Bancos"], ["/admin/numeracion", "Numeración"], ["/admin/api", "API"]] },
  { titulo: "Sistema", items: [["/admin/personal", "Personal"], ["/admin/procesos", "Procesos"], ["/admin/settings", "Configuración"], ["/admin/console", "Consola"]] },
];

export default function AdminLayout({ children }: { children: React.ReactNode }) {
  const [state, setState] = useState<"load" | "out" | "in" | "err">("load");
  const [msg, setMsg] = useState("");
  const [abierto, setAbierto] = useState(false);
  const ruta = usePathname() ?? "/admin";

  useEffect(() => {
    let off = () => {};
    initSb()
      .then(() => {
        sb().auth.getSession().then(({ data }) => setState(data.session ? "in" : "out"));
        const { data: l } = sb().auth.onAuthStateChange((_e, s) => setState(s ? "in" : "out"));
        off = () => l.subscription.unsubscribe();
      })
      .catch((e) => { setMsg((e as Error).message); setState("err"); });
    return () => off();
  }, []);

  const entrar = async (e: React.FormEvent<HTMLFormElement>) => {
    e.preventDefault();
    const f = new FormData(e.currentTarget);
    const { error } = await sb().auth.signInWithPassword({ email: String(f.get("e")), password: String(f.get("p")) });
    if (error) setMsg(error.message);
  };

  const activo = (h: string) => (h === "/admin" ? ruta === "/admin" : ruta.startsWith(h));

  if (state === "load") return <div className="login"><p className="muted" role="status">Cargando el panel…</p></div>;
  if (state === "err") return (
    <main className="login"><h1>Configuración incompleta</h1><p role="alert" style={{ color: "#a33" }}>{msg}</p>
      <p>Añade las variables de entorno en Vercel (Settings → Environment Variables) y vuelve a desplegar.</p></main>);
  if (state === "out") return (
    <main className="login"><h1>Placeta One</h1><p className="muted">Acceso del personal</p>
      {msg && <p role="alert" style={{ color: "#a33" }}>{msg}</p>}
      <form onSubmit={entrar}><input name="e" type="email" placeholder="Correo" required autoComplete="username" />
        <input name="p" type="password" placeholder="Contraseña" required autoComplete="current-password" /><button className="btn btn-primary">Entrar</button></form></main>);

  return (
    <div className="shell">
      <header className="topbar">
        <button className="menu-btn" aria-label="Abrir menú" aria-expanded={abierto} onClick={() => setAbierto(!abierto)}>☰ Menú</button>
        <b>Placeta One</b>
      </header>
      <aside className={`side${abierto ? " open" : ""}`} aria-label="Navegación principal">
        <div className="brand">Placeta One<small>Grupo de La Placeta · Plan 2027</small></div>
        {GRUPOS.map((g) => (
          <div className="grupo" key={g.titulo}>
            <div className="grupo-t">{g.titulo}</div>
            {g.items.map(([h, l]) => (
              <Link key={h} href={h} className={activo(h) ? "on" : undefined} aria-current={activo(h) ? "page" : undefined} onClick={() => setAbierto(false)}>{l}</Link>
            ))}
          </div>
        ))}
        <button className="btn salir" onClick={() => sb().auth.signOut()}>Salir</button>
      </aside>
      <main className="main" id="contenido">{children}<DialogHost /></main>
    </div>
  );
}
