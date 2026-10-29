import { redirect } from "next/navigation";
// La entrada a la plataforma es el panel de administración.
export default function Home() {
  redirect("/admin");
}
