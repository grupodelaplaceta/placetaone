// Generador mínimo de PDF de texto (Helvetica, una página A4), sin dependencias externas.
// Las líneas se truncan a 48 y se escapan los caracteres especiales del formato PDF.
export function generarPdf(lineas: string[]): Buffer {
  const texto = lineas.slice(0, 48).map((l) => l.replace(/[\r\n]/g, " ").replace(/[\\()]/g, (m) => "\\" + m));
  let contenido = "BT /F1 11 Tf 16 TL 50 800 Td\n";
  for (const l of texto) contenido += `(${l}) Tj T*\n`;
  contenido += "ET\n";
  const cont = Buffer.from(contenido, "latin1");
  const objs: Buffer[] = [
    Buffer.from("<< /Type /Catalog /Pages 2 0 R >>", "latin1"),
    Buffer.from("<< /Type /Pages /Kids [3 0 R] /Count 1 >>", "latin1"),
    Buffer.from("<< /Type /Page /Parent 2 0 R /MediaBox [0 0 595 842] /Contents 4 0 R /Resources << /Font << /F1 5 0 R >> >> >>", "latin1"),
    Buffer.concat([Buffer.from(`<< /Length ${cont.length} >>\nstream\n`, "latin1"), cont, Buffer.from("\nendstream", "latin1")]),
    Buffer.from("<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica /Encoding /WinAnsiEncoding >>", "latin1"),
  ];
  const partes: Buffer[] = [Buffer.from("%PDF-1.4\n", "latin1")];
  const offsets: number[] = [];
  let pos = partes[0].length;
  objs.forEach((o, i) => {
    const cab = Buffer.from(`${i + 1} 0 obj\n`, "latin1");
    const pie = Buffer.from("\nendobj\n", "latin1");
    offsets.push(pos);
    partes.push(cab, o, pie);
    pos += cab.length + o.length + pie.length;
  });
  let xref = `xref\n0 ${objs.length + 1}\n0000000000 65535 f \n`;
  for (const o of offsets) xref += String(o).padStart(10, "0") + " 00000 n \n";
  xref += `trailer\n<< /Size ${objs.length + 1} /Root 1 0 R >>\nstartxref\n${pos}\n%%EOF\n`;
  partes.push(Buffer.from(xref, "latin1"));
  return Buffer.concat(partes);
}
