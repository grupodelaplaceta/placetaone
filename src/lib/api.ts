import { sb } from "./browser";
export async function api(path: string, method = "GET", body?: object) {
  const { data } = await sb().auth.getSession();
  const r = await fetch(path, { method, headers: { authorization: `Bearer ${data.session?.access_token ?? ""}`, "content-type": "application/json" }, body: body ? JSON.stringify(body) : undefined });
  const j = await r.json().catch(() => ({}));
  if (!r.ok) throw new Error(j.error || "Error");
  return j;
}
