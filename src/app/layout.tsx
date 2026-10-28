export const metadata = { title: "Placeta One", description: "Portal administrativo de Grupo de La Placeta · Pz" };
export default function Root({ children }: { children: React.ReactNode }) {
  return (<html lang="es"><body style={{ fontFamily: "system-ui", margin: 0, background: "#f6f5f1", color: "#1b1b18" }}>{children}</body></html>);
}
