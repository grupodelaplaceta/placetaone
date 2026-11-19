import { admin } from "./supabase";

// Logos en el bucket público "branding". Comprobaciones sobre el contenido real del archivo:
// formato (cabeceras y estructura completa), dimensiones, proporción, peso y ausencia de marcado incrustado.
// Solo PNG, JPG y WEBP. No se acepta SVG (puede llevar scripts).
const MAX_BYTES = 512 * 1024;
const LADO_MIN = 32;
const LADO_MAX = 2048;
const PROPORCION_MAX = 4;
const PNG_SIG = Buffer.from([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]);
const PNG_IEND = Buffer.from([0, 0, 0, 0, 0x49, 0x45, 0x4e, 0x44, 0xae, 0x42, 0x60, 0x82]);
const MARCADO_PROHIBIDO = /<script|<svg|<html|<iframe|javascript:|<\?php|<!doctype/i;

type Dim = { w: number; h: number };

function dimensionesJpeg(b: Buffer): Dim | null {
  let i = 2;
  while (i + 9 < b.length) {
    if (b[i] !== 0xff) { i++; continue; }
    const m = b[i + 1];
    if (m === 0xd8 || m === 0x01 || (m >= 0xd0 && m <= 0xd7) || m === 0xff) { i += 1; continue; }
    const len = b.readUInt16BE(i + 2);
    if (m >= 0xc0 && m <= 0xcf && m !== 0xc4 && m !== 0xc8 && m !== 0xcc) {
      return { h: b.readUInt16BE(i + 5), w: b.readUInt16BE(i + 7) };
    }
    i += 2 + len;
  }
  return null;
}

function dimensionesWebp(b: Buffer): Dim | null {
  const t = b.subarray(12, 16).toString("ascii");
  if (t === "VP8 ") return { w: b.readUInt16LE(26) & 0x3fff, h: b.readUInt16LE(28) & 0x3fff };
  if (t === "VP8L") { const bits = b.readUInt32LE(21); return { w: (bits & 0x3fff) + 1, h: ((bits >>> 14) & 0x3fff) + 1 }; }
  if (t === "VP8X") return { w: 1 + b.readUIntLE(24, 3), h: 1 + b.readUIntLE(27, 3) };
  return null;
}

export type Imagen = { ext: string; mime: string; ancho: number; alto: number };

// Devuelve el tipo y las dimensiones, o el motivo del rechazo
export function leerImagen(b: Buffer): Imagen | { error: string } {
  if (b.length < 32) return { error: "La imagen es demasiado pequeña o no es válida" };
  if (MARCADO_PROHIBIDO.test(b.toString("latin1"))) return { error: "La imagen contiene marcado no permitido" };
  let ext = "", mime = "", d: Dim | null = null;
  if (b.subarray(0, 8).equals(PNG_SIG)) {
    if (b.subarray(12, 16).toString("ascii") !== "IHDR") return { error: "PNG sin cabecera IHDR" };
    if (!b.subarray(b.length - 12).equals(PNG_IEND)) return { error: "PNG incompleto o dañado" };
    ext = "png"; mime = "image/png"; d = { w: b.readUInt32BE(16), h: b.readUInt32BE(20) };
  } else if (b[0] === 0xff && b[1] === 0xd8 && b[2] === 0xff) {
    if (!(b[b.length - 2] === 0xff && b[b.length - 1] === 0xd9)) return { error: "JPG incompleto o dañado" };
    ext = "jpg"; mime = "image/jpeg"; d = dimensionesJpeg(b);
  } else if (b.subarray(0, 4).toString("ascii") === "RIFF" && b.subarray(8, 12).toString("ascii") === "WEBP") {
    if (b.readUInt32LE(4) + 8 !== b.length) return { error: "WEBP incompleto o dañado" };
    ext = "webp"; mime = "image/webp"; d = dimensionesWebp(b);
  } else {
    return { error: "Formato no permitido: PNG, JPG o WEBP" };
  }
  if (!d || d.w <= 0 || d.h <= 0) return { error: "No se pueden leer las dimensiones de la imagen" };
  const menor = Math.min(d.w, d.h), mayor = Math.max(d.w, d.h);
  if (menor < LADO_MIN) return { error: `Cada lado debe medir al menos ${LADO_MIN} px` };
  if (mayor > LADO_MAX) return { error: `Ningún lado puede superar ${LADO_MAX} px` };
  if (mayor / menor > PROPORCION_MAX) return { error: `La proporción no puede superar ${PROPORCION_MAX}:1` };
  return { ext, mime, ancho: d.w, alto: d.h };
}

export async function subirLogo(carpeta: string, base64: string): Promise<{ url: string; ancho: number; alto: number } | { error: string }> {
  const buf = Buffer.from(base64.replace(/^data:[^;]+;base64,/, ""), "base64");
  if (buf.length === 0 || buf.length > MAX_BYTES) return { error: "La imagen debe pesar entre 1 byte y 512 KB" };
  const t = leerImagen(buf);
  if ("error" in t) return t;
  const ruta = `${carpeta}/${Date.now()}.${t.ext}`;
  const db = admin();
  const up = await db.storage.from("branding").upload(ruta, buf, { contentType: t.mime, upsert: false });
  if (up.error) return { error: up.error.message };
  return { url: db.storage.from("branding").getPublicUrl(ruta).data.publicUrl, ancho: t.ancho, alto: t.alto };
}
