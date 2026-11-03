"use client";
import { useEffect, useState } from "react";
type D = { kind: "confirm" | "prompt"; msg: string; res: (v: string | boolean | null) => void };
let push: (d: D) => void = () => {};
export const dlg = {
  confirm: (msg: string) => new Promise<boolean>(r => push({ kind: "confirm", msg, res: v => r(!!v) })),
  prompt: (msg: string) => new Promise<string | null>(r => push({ kind: "prompt", msg, res: v => r(v as string | null) })),
};
export function Overlay({ children, onClose, bottom }: { children: React.ReactNode; onClose: () => void; bottom?: boolean }) {
  return (<div onClick={onClose} style={{ position: "fixed", inset: 0, background: "rgba(0,0,0,.45)", display: "flex", alignItems: bottom ? "flex-end" : "center", justifyContent: "center", zIndex: 50 }}>
    <div onClick={e => e.stopPropagation()} role="dialog" style={{ background: "#fff", borderRadius: bottom ? "16px 16px 0 0" : 12, padding: 20, width: "min(620px,100%)", maxHeight: "88vh", overflow: "auto", animation: "pl-up .2s ease-out" }}>{children}</div>
    <style>{"@keyframes pl-up{from{transform:translateY(40px);opacity:0}to{transform:none;opacity:1}}"}</style></div>);
}
export const Sheet = ({ open, title, onClose, children }: { open: boolean; title: string; onClose: () => void; children: React.ReactNode }) => !open ? null :
  <Overlay bottom onClose={onClose}><div style={{ display: "flex", justifyContent: "space-between", marginBottom: 12 }}><h3 style={{ margin: 0 }}>{title}</h3><button onClick={onClose} aria-label="Cerrar">✕</button></div>{children}</Overlay>;
export const Modal = Sheet;
export function DialogHost() {
  const [d, setD] = useState<D | null>(null); const [v, setV] = useState("");
  useEffect(() => { push = x => { setV(""); setD(x); }; }, []);
  if (!d) return null; const close = (x: string | boolean | null) => { d.res(x); setD(null); };
  return (<Overlay onClose={() => close(d.kind === "confirm" ? false : null)}><p style={{ whiteSpace: "pre-wrap", marginTop: 0 }}>{d.msg}</p>
    {d.kind === "prompt" && <input autoFocus value={v} onChange={e => setV(e.target.value)} onKeyDown={e => e.key === "Enter" && close(v)} style={{ width: "100%", boxSizing: "border-box" }} />}
    <div style={{ display: "flex", gap: 8, justifyContent: "flex-end", marginTop: 16 }}><button onClick={() => close(d.kind === "confirm" ? false : null)}>Cancelar</button><button onClick={() => close(d.kind === "confirm" ? true : v)}>Aceptar</button></div></Overlay>);
}
