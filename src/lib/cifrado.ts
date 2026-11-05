import { createCipheriv, createDecipheriv, createHash, randomBytes } from "crypto";

// Cifrado de los secretos de webhook con AES-256-GCM. La clave sale de WEBHOOK_KEY (mínimo 24 caracteres).
// Los secretos antiguos, sin cifrar, siguen funcionando hasta que se roten.
const PREFIJO = "enc:v1:";

function clave(): Buffer {
  const k = process.env.WEBHOOK_KEY;
  if (!k || k.length < 24) throw new Error("WEBHOOK_KEY no configurada (mínimo 24 caracteres)");
  return createHash("sha256").update(k).digest();
}

export function cifrarSecreto(texto: string): string {
  const iv = randomBytes(12);
  const c = createCipheriv("aes-256-gcm", clave(), iv);
  const ct = Buffer.concat([c.update(texto, "utf8"), c.final()]);
  return PREFIJO + Buffer.concat([iv, c.getAuthTag(), ct]).toString("base64");
}

export function descifrarSecreto(valor: string): string {
  if (!valor.startsWith(PREFIJO)) return valor;
  const buf = Buffer.from(valor.slice(PREFIJO.length), "base64");
  const d = createDecipheriv("aes-256-gcm", clave(), buf.subarray(0, 12));
  d.setAuthTag(buf.subarray(12, 28));
  return Buffer.concat([d.update(buf.subarray(28)), d.final()]).toString("utf8");
}
