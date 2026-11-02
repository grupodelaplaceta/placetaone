"use client";
import { useCallback, useEffect, useRef, useState } from "react";
import { api } from "@/lib/api";

// Componentes y datos comunes del panel. Nada aquí asume que la API responde con la forma prevista.
export type Tono = "ok" | "warn" | "bad" | "info" | "neutral";
export const arr = <T = any>(x: unknown): T[] => (Array.isArray(x) ? (x as T[]) : []);
export const pz = (n: number | string | null | undefined) => {
  const v = Number(n);
  return n == null || Number.isNaN(v) ? "—" : `${v.toLocaleString("es-ES", { minimumFractionDigits: 2, maximumFractionDigits: 2 })} Pz`;
};
export const fecha = (s?: string | null) => (s ? new Date(s).toLocaleString("es", { dateStyle: "short", timeStyle: "short" }) : "—");

// Carga datos de la API con estados de cargando, error y reintento. Cancela la actualización si la pantalla ya no existe.
export function useApi<T extends object>(path: string | null, inicial: T) {
  const [data, setData] = useState<T>(inicial);
  const [error, setError] = useState("");
  const [loading, setLoading] = useState(!!path);
  const vivo = useRef(true);
  const reload = useCallback(async () => {
    if (!path) return;
    setLoading(true); setError("");
    try { const j = await api(path); if (vivo.current) setData((j ?? {}) as T); }
    catch (e) { if (vivo.current) setError((e as Error).message || "No se pudo cargar"); }
    finally { if (vivo.current) setLoading(false); }
  }, [path]);
  useEffect(() => { vivo.current = true; reload(); return () => { vivo.current = false; }; }, [reload]);
  return { data, error, loading, reload, setData };
}

export function Card({ titulo, acciones, children }: { titulo: string; acciones?: React.ReactNode; children: React.ReactNode }) {
  return (<section className="card"><header className="card-h"><h2>{titulo}</h2>{acciones && <div className="card-a">{acciones}</div>}</header>{children}</section>);
}
export function Stat({ label, value, hint, tono = "neutral" }: { label: string; value: string | number; hint?: string; tono?: Tono }) {
  return (<div className={`stat stat-${tono}`}><div className="stat-l">{label}</div><div className="stat-v">{value}</div>{hint && <div className="stat-h">{hint}</div>}</div>);
}
export function Badge({ tono = "neutral", children }: { tono?: Tono; children: React.ReactNode }) {
  return <span className={`badge badge-${tono}`}>{children}</span>;
}
export function Loading({ texto = "Cargando…" }: { texto?: string }) {
  return (<div className="estado muted" role="status"><span className="spin" />{texto}</div>);
}
export function Empty({ texto }: { texto: string }) {
  return <div className="estado muted">{texto}</div>;
}
export function ErrorBox({ mensaje, onRetry }: { mensaje: string; onRetry?: () => void }) {
  return (<div role="alert" className="err"><b>No se ha podido cargar.</b> <span>{mensaje}</span>{onRetry && <button className="btn" onClick={onRetry}>Reintentar</button>}</div>);
}
