// Texto del contrato de pasarela de una empresa. Nunca incluye la clave de API: se entrega una sola vez en el alta.
export function textoContrato(d: { banco: string; empresa: string; fiscal: string; version: number; scopes: string[]; base: string; clienteNombre: string }): string {
  return [
    "CONTRATO DE PASARELA DE PAGO",
    `Entidad: ${d.banco}`,
    `Empresa: ${d.empresa} (identificador fiscal ${d.fiscal})`,
    `Cliente de API: ${d.clienteNombre}`,
    `Versión del contrato: ${d.version}`,
    "",
    "1. Credenciales. La clave de API se entregó una sola vez, en la respuesta del alta. Guárdala en un gestor de secretos. No se puede recuperar: si se pierde, la entidad debe emitir una nueva.",
    `2. Acceso. Base de la API: ${d.base}/api. Cada petición lleva la cabecera x-api-key con tu clave. Permisos concedidos: ${d.scopes.join(", ")}.`,
    "3. Cobros. Crea pagos con POST /api/v1/bk/checkouts. Solo se cobra a cuentas de tu empresa. El cliente confirma el pago en la app de su banco con el código de pago.",
    "4. Webhooks. Da de alta una URL https con POST /api/v1/bk/webhooks y verifica cada entrega con la cabecera x-placeta-signature (HMAC-SHA256 del cuerpo con el secreto del webhook).",
    "5. Navegador. Si tu web llama a la API desde el navegador, solicita su origen con POST /api/v1/bk/origenes. Sin origen aprobado, el navegador no recibe respuesta.",
    "6. Tarjetas NFC. Registra el identificador o el enlace NFC de tus tarjetas con PUT /api/v1/bk/tarjetas/{ref}/nfc.",
    "7. Comisiones. Se aplican según la tarifa vigente de la entidad. La ventana de pago puede mostrar: Tu entidad de pagos del ecosistema Placeta puede aplicar otras comisiones extra a las mostradas.",
    "8. Titulares. La empresa la administran sus titulares. Las altas y los ceses los gestiona la entidad y los titulares de la empresa.",
    "9. Seguridad. La clave no debe incluirse en código de navegador: llama a la API desde tu backend.",
  ].join("\n");
}
