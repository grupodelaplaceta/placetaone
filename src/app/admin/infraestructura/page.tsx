"use client";
import { useEffect, useState } from "react";
import { api } from "@/lib/api";

// Panel explicativo de toda la infraestructura. Cada tarjeta explica qué es, cómo funciona, un ejemplo y la norma que lo sustenta.
type D = any;
type Tarjeta = { id: string; titulo: string; resume: string; como: string[]; ejemplo: string; norma: string; ir?: { href: string; texto: string };
  datos: (d: D) => [string, string | number][]; barras?: (d: D) => { k: string; v: number }[] };

const pz = (n: number) => `${Number(n || 0).toLocaleString("es-ES", { minimumFractionDigits: 2, maximumFractionDigits: 2 })} Pz`;
const box = { background: "#fff", border: "1px solid #ddd", borderRadius: 10, padding: 16, marginBottom: 16 } as const;
const chip = { display: "inline-block", background: "#f1efe8", borderRadius: 6, padding: "2px 8px", margin: "2px 4px 2px 0", fontSize: 13 } as const;
const estado = (c: Record<string, number>, k: string) => c?.[k] ?? 0;

function Barras({ items }: { items: { k: string; v: number }[] }) {
  const max = Math.max(1, ...items.map((i) => i.v));
  return <div style={{ marginTop: 8 }}>{items.map((i) => (
    <div key={i.k} style={{ display: "grid", gridTemplateColumns: "180px 1fr 50px", gap: 8, alignItems: "center", fontSize: 13, marginBottom: 4 }}>
      <span>{i.k}</span>
      <div style={{ background: "#eee", borderRadius: 4, height: 10 }}><div style={{ width: `${Math.round((i.v / max) * 100)}%`, background: "#3a6", height: 10, borderRadius: 4 }} /></div>
      <b style={{ textAlign: "right" }}>{i.v}</b></div>))}</div>;
}

const TARJETAS: Tarjeta[] = [
  { id: "entidades", titulo: "Entidades y cuentas con IBAN",
    resume: "Cada entidad bancaria tiene un código de cuatro cifras. Cada cuenta tiene un IBAN propio con formato PZ-EEEE-CCCC, que genera el servidor y no se puede cambiar.",
    como: ["Cada entidad tiene una cuenta principal, desde la que sale el capital de sus cuotas y a la que llegan sus intereses.", "Tiene también una cuenta de impuestos. Por defecto es la principal, pero cada entidad puede elegir otra.", "Las cuentas de la entidad 0000 son institucionales: Reserva, Tributos y Placeta Junior."],
    ejemplo: "La entidad 0001 tiene la cuenta principal PZ-0001-0002. Una cuota de 1.066,19 Pz sale de la cuenta del cliente y entra en esa principal.",
    norma: "Art. T9 (Banco de La Placeta como infraestructura), Art. T93, Anexo III.", ir: { href: "/admin/bancos", texto: "Ver entidades" },
    datos: (d) => [["Entidades activas", `${d.entidades.activas} de ${d.entidades.total}`], ["Entidades sin cuenta principal", d.entidades.sin_cuenta_principal], ["Cuentas", d.cuentas.total], ["Cuentas activas", d.cuentas.activas]] },
  { id: "institucionales", titulo: "Cuentas institucionales",
    resume: "Son las cuentas que la propia Placeta usa para recibir o pagar fondos de interés general. Solo las cuentas institucionales pueden recibir impuestos y financiar la RBU.",
    como: ["Reserva del Grupo: recibe las cotizaciones (empresa y trabajador) y, por defecto, financia la RBU.", "Tributos: recibe los impuestos. Tiene IBAN propio.", "Placeta Junior · pagos asumidos: paga las operaciones Junior si Capitalia no lo hace.", "Cuenta principal de Capitalia: paga en nombre de los usuarios Junior."],
    ejemplo: "Un recibo de IVA de 120 Pz se cobra de la cuenta del vendedor y entra en la cuenta de Tributos.",
    norma: "Arts. 4.4 y 4.5, T19 a T21, Anexo III; instrucción de la segunda ronda sobre Capitalia.", ir: { href: "/admin/destinos", texto: "Configurar cuentas" },
    datos: (d) => [["Institucionales", d.institucionales.total], ["Sin aprobador registrado", d.institucionales.sin_aprobador], ["Que pueden operar con Junior", d.institucionales.junior]] },
  { id: "destinos", titulo: "Destino de cada impuesto",
    resume: "Cada impuesto tiene una cuenta de destino, con IBAN, donde se ingresa lo que se recauda. Se configura en Destinos.",
    como: ["Solo se puede elegir una cuenta institucional.", "Cada cambio queda registrado en auditoría con el valor anterior y el nuevo.", "Los recibos que se cobren después del cambio van a la nueva cuenta."],
    ejemplo: "Si el IRP pasa a destinarse a Tributos, las nóminas que se paguen a partir de entonces lo ingresan allí. Las ya pagadas no cambian.",
    norma: "Art. T3.2 y Art. T93: los elementos de un tributo los aprueba la Junta. Art. T6: gestión de la Administración.", ir: { href: "/admin/destinos", texto: "Cambiar destinos" },
    datos: (d) => d.impuestos.reglas.slice(0, 0).concat([["Impuestos configurados", d.impuestos.reglas.length]]) as [string, number][],
    barras: (d) => Object.entries(d.impuestos.por_destino).map(([k, v]) => ({ k: k.slice(0, 40), v: Number(v) })) },
  { id: "impuestos", titulo: "Impuestos y tramos",
    resume: "Cada impuesto es una norma con versiones: tipo o tramos, fecha de entrada en vigor y una huella que identifica su contenido. Una versión publicada no se modifica.",
    como: ["Borrador: se puede editar. No genera recibos.", "Publicada: exige un aprobador distinto de su autor. Sus tramos quedan bloqueados.", "Huella: resumen SHA-256 del contenido. Si algo cambiara, la verificación lo detectaría."],
    ejemplo: "IGF: un patrimonio de 900.000 Pz paga 106.400 Pz. Cada tramo solo tributa la parte que cae en él.",
    norma: "Arts. T2 y T3 (legalidad y competencia), T14–T15 (progresividad), T26–T47 (tipos y tramos), T98 (entrada en vigor).",
    datos: (d) => [["Versiones publicadas", d.impuestos.versiones.publicadas], ["Borradores pendientes", d.impuestos.versiones.borrador]] },
  { id: "recibos", titulo: "Recibos y cobro automático",
    resume: "Un impuesto calculado genera un recibo con importe, vencimiento y estado. El cobro se hace solo en la fecha de vencimiento, si la cuenta tiene fondos.",
    como: ["Emitido: pendiente de pago.", "Parcial: se ha pagado una parte.", "Pagado: cobrado y contabilizado.", "Sin fondos: el recibo queda pendiente y se reintenta cada día sin duplicar el cobro."],
    ejemplo: "Recibo de IVA de 120 Pz con vencimiento el 15 de enero. Si el 15 la cuenta tiene 200 Pz, se cobran 120 Pz sin que nadie haga nada.",
    norma: "Arts. T13 (plazos), T54 (pago), T57 (recargo por retraso).",
    datos: (d) => [["Pendiente de cobro", pz(d.recibos.pendiente_importe)], ["Emitidos", estado(d.recibos.por_estado, "issued")], ["Pagados", estado(d.recibos.por_estado, "paid")]],
    barras: (d) => Object.entries(d.recibos.por_estado).map(([k, v]) => ({ k, v: Number(v) })) },
  { id: "certificados", titulo: "Certificados de cálculo",
    resume: "Cada recibo tiene un certificado: la norma usada, la base, el desglose por tramos, el importe y un hash encadenado con el anterior. Demuestra que el importe sale de la norma.",
    como: ["El certificado acredita el cálculo. No acredita que la base sea verdadera (Art. T103).", "Si un recibo cambia, se emite un certificado nuevo que apunta al anterior. El anterior no se modifica.", "El informe de veracidad recalcula toda la cadena cada día."],
    ejemplo: "Recibo de 1.000 Pz con IVA del 12 %: certificado nº 4821, importe 120 Pz. Una nota de crédito a 900 Pz genera el certificado nº 4870, que apunta al 4821.",
    norma: "Arts. T102 a T104 y T110.",
    datos: (d) => [["Estado del informe", d.certificados.estado ?? "—"], ["Certificados", d.certificados.certificados ?? 0], ["Cadena rota", d.certificados.cadena_rota ?? 0], ["Recibos sin certificado", d.certificados.recibos_sin_certificado ?? 0], ["Importes que no recalculan", d.certificados.importes_no_recalculan ?? 0]] },
  { id: "iva-ventas", titulo: "IVA en las ventas",
    resume: "Toda venta dentro del sistema lleva IVA del 12 % sobre el precio base. El comprador paga base más IVA, y el vendedor liquida el IVA.",
    como: ["La venta queda registrada en el libro de ventas.", "El IVA es un recibo a cargo del vendedor, cobrado automáticamente.", "Las exenciones se registran con su fundamento legal y no generan IVA."],
    ejemplo: "Venta de 1.000 Pz de base: el comprador paga 1.120 Pz y el vendedor debe 120 Pz de IVA.",
    norma: "Art. 4.4, Arts. T26 a T28 y T106.",
    datos: (d) => [["Ventas registradas", d.iva.ventas.operaciones], ["Base vendida", pz(d.iva.ventas.base)], ["IVA cobrado en ventas", pz(d.iva.ventas.iva)]] },
  { id: "deteccion", titulo: "Transferencias comerciales sin IVA",
    resume: "Cada día el escaneo busca cobros comerciales que no tienen venta registrada. Es una detección: no bloquea ni cobra nada. Lo encontrado se revisa en IVA.",
    como: ["Cobro comercial sin IVA: una transferencia entra en una cuenta de empresa sin venta registrada.", "Patrón comercial en cuenta personal: una cuenta personal recibe de muchos pagadores distintos en 30 días.", "Fraccionamiento: varias transferencias pequeñas del mismo pagador al mismo comercio en un día que suman más del umbral."],
    ejemplo: "Una empresa recibe tres transferencias de 300 Pz en un día desde la misma cuenta: 900 Pz de fraccionamiento, con 108 Pz de IVA estimado.",
    norma: "Art. T67 a) (omitir una operación sujeta, infracción grave), Art. T69 a) y d) (fraude y operaciones ficticias), Art. T106.", ir: { href: "/admin/iva", texto: "Revisar hallazgos" },
    datos: (d) => [["Hallazgos abiertos", d.iva.abiertos], ["Importe abierto", pz(d.iva.importe_abierto)], ["IVA estimado pendiente", pz(d.iva.iva_abierto)]],
    barras: (d) => Object.entries(d.iva.por_severidad).map(([k, v]) => ({ k: `Severidad ${k}`, v: Number(v) })) },
  { id: "regularizacion", titulo: "Regularización y reporte de IVA",
    resume: "Un hallazgo se regulariza emitiendo el recibo de IVA y registrando la venta. Quien propone no puede aprobar: son dos personas distintas.",
    como: ["Proponer: el fiscal indica si regularizar o descartar, con un motivo.", "Aprobar: un aprobador distinto confirma. Solo entonces se emite el recibo.", "Informe: IVA pendiente y regularizado por periodo, exportable a CSV."],
    ejemplo: "Hallazgo de 1.000 Pz sin IVA. Se propone regularizar: el IVA es 120 Pz. El aprobador lo confirma y el recibo queda a cargo del receptor.",
    norma: "Art. T7 (Departamento de Tributos), Art. T109 (separación de funciones), Art. T106.", ir: { href: "/admin/iva", texto: "Ir a IVA" },
    datos: (d) => [["IVA regularizado", pz(d.iva.ventas.iva)], ["Hallazgos totales", Object.values(d.iva.hallazgos_por_estado).reduce((a: number, b) => a + Number(b), 0)]] },
  { id: "junior", titulo: "Usuarios Junior y Capitalia",
    resume: "Los usuarios Junior tienen cuentas aisladas. Solo pueden operar con cuentas institucionales que la Junta haya marcado. Capitalia paga sus impuestos en su nombre.",
    como: ["Junior con Junior: permitido, como antes.", "Junior con una cuenta institucional marcada: permitido.", "Junior con un cliente habitual (personal, compartida o de empresa): bloqueado.", "Impuestos Junior: se cobran de la cuenta de Capitalia. El obligado queda registrado como el usuario Junior."],
    ejemplo: "Un Junior paga su membresía mensual a la cuenta de cuotas de Placeta Junior, que está marcada: permitido. Un pago a un comercio personal: bloqueado.",
    norma: "Arts. T17 a T23, Anexo III, y la instrucción de la segunda ronda sobre Capitalia.", ir: { href: "/admin/destinos", texto: "Marcar cuentas" },
    datos: (d) => [["Cuentas Junior", d.junior.cuentas], ["Institucionales que operan con Junior", d.institucionales.junior], ["Pagador de impuestos Junior", d.junior.capitalia]] },
  { id: "nominas", titulo: "Nóminas y cotizaciones",
    resume: "Cada contrato se valida contra el SMI, que es de 160 Pz al mes para jornada completa. Cada mes la empresa paga el bruto, y las cotizaciones y el IRP van a sus cuentas destino.",
    como: ["El contrato no se valida si el bruto mensual es menor de 160 Pz.", "La cotización de empresa y la del trabajador van a Reserva. El IRP va a su destino.", "La nómina se paga sola el día configurado (por defecto, el 28)."],
    ejemplo: "Bruto de 1.500 Pz: cotización del trabajador 112,50 Pz, de la empresa 112,50 Pz e IRP 75 Pz. El trabajador recibe 1.312,50 Pz.",
    norma: "Art. 4.5 (cotizaciones), Art. 4.7 (SMI), Arts. T35 y T36 (IRP), y la instrucción de 160 Pz al mes.",
    datos: (d) => [["SMI mensual", pz(d.ajustes.smi_mensual_completa_pz as number)], ["Contratos activos", d.nominas.contratos_activos], ["Nóminas emitidas", d.nominas.nominas_emitidas], ["Neto pagado", pz(d.nominas.neto_total)]] },
  { id: "rbu", titulo: "Renta Básica Universal (RBU)",
    resume: "Cada semana se emite un bono de 5 Pz a cada titular activo. El bono sale de la cuenta de origen de la RBU, con IBAN. No se cobra solo: el titular lo reclama, y si no lo hace, caduca.",
    como: ["La cuenta de origen se configura en Destinos. Por defecto es la Reserva.", "El dinero va a una cartera de RBU que no es embargable.", "Los menores con ficha Junior no reciben la RBU."],
    ejemplo: "El titular ve «Reclamar 5 Pz (caduca el 2 de noviembre)». Al reclamar, los 5 Pz pasan de la cuenta de origen a su cartera.",
    norma: "Art. 4.6 (RBU) y Art. 4.7.", ir: { href: "/admin/destinos", texto: "Cambiar origen" },
    datos: (d) => [["Disponibles", estado(d.rbu.por_estado, "available")], ["Reclamadas", estado(d.rbu.por_estado, "claimed")], ["Caducadas", estado(d.rbu.por_estado, "expired")], ["Importe disponible", pz(d.rbu.importe_disponible)]],
    barras: (d) => Object.entries(d.rbu.por_estado).map(([k, v]) => ({ k, v: Number(v) })) },
  { id: "planes", titulo: "Pagos a plazos y suscripciones",
    resume: "Un plan de cuotas usa cuota constante. El interés es el que fija la entidad, de forma automática, y lo cobra su cuenta principal. Una suscripción cobra el mismo importe cada mes, en el mismo día.",
    como: ["Fecha de cálculo: la fecha de inicio desde la que se devenga el interés.", "Cada cuota es capital más interés. La cuenta principal de la entidad cobra ambos.", "Sin fondos, la cuota queda pendiente y se reintenta cada día."],
    ejemplo: "12.000 Pz en 12 meses al 12 % anual: cuota de 1.066,19 Pz. Primer mes: 120,00 Pz de interés y 946,19 Pz de capital. (El tipo del ejemplo no está aprobado.)",
    norma: "Sin artículo propio todavía: falta la norma de crédito (ver el anexo de decisiones de la normativa).",
    datos: (d) => [["Planes activos", d.planes.activos], ["Cuotas pendientes", d.planes.cuotas_pendientes], ["Tipo de interés actual", `${d.ajustes.interes_anual_pct ?? 0} %`]] },
  { id: "mora", titulo: "Mora y recargos (T57)",
    resume: "Un recibo vencido genera un recargo según los días de retraso. El recargo se calcula sobre lo pendiente, se cobra como deuda y se certifica.",
    como: ["Hasta 7 días: 1 %. De 8 a 30: 3 %. De 31 a 90: 5 %. De 91 a 180: 10 %. Más de 180: 15 %.", "Cuando el tramo sube, se cobra solo la diferencia. Si lo pendiente baja, no se devuelve nada.", "El interés de demora por segundo (Art. 4.3) está desactivado: lo sustituye T57."],
    ejemplo: "Recibo de 200 Pz vencido hace 10 días: recargo del 3 %, es decir 6 Pz. A los 35 días el tramo sube al 5 %: se cobra la diferencia hasta 10 Pz.",
    norma: "Art. T57, que prevalece sobre el Art. 4.3 (Art. T100).",
    datos: (d) => [["Demora por segundo", d.ajustes.demora_habilitada ? "activa" : "desactivada"], ["Recargos T57 activos", d.ajustes.late_penalty_enabled ? "sí" : "no"]] },
  { id: "procesos", titulo: "Procesos diarios e incidencias",
    resume: "Cada día a las 04:00 se ejecutan los procesos: RBU, programadas, cuotas de producto, intereses, membresías, nóminas, planes, IAEP, mora, recargos, escaneo de IVA, cobros y certificación. Un paso que falla no detiene a los demás.",
    como: ["Cada paso queda en su propio bloque. Si falla, se registra como incidencia.", "Todos son idempotentes: relanzarlos no duplica cobros ni recibos.", "El informe de certificación abre una incidencia si algo no cuadra."],
    ejemplo: "Una nómina falla por falta de fondos: aparece como incidencia «nomina_fallida» y se reintenta al día siguiente.",
    norma: "Art. T109 (controles adicionales).",
    datos: (d) => [["Incidencias abiertas", Object.values(d.incidencias).reduce((a: number, b) => a + Number(b), 0)]],
    barras: (d) => Object.entries(d.incidencias).map(([k, v]) => ({ k, v: Number(v) })) },
  { id: "normas", titulo: "Normas, ajustes y aprobaciones",
    resume: "Ningún cambio fiscal entra sin la aprobación de otra persona. Las versiones de norma se publican con dos firmas. Los ajustes sensibles se proponen y se aprueban.",
    como: ["Publicar una norma: el autor y el aprobador son personas distintas.", "Cambiar un ajuste sensible: se propone, otra persona lo aprueba, y queda registrado.", "La auditoría es de solo añadir: nada se borra."],
    ejemplo: "Un fiscal crea el IVA versión 2. Un aprobador la revisa y la publica. Desde ese momento la huella queda fijada.",
    norma: "Art. T3 (competencia normativa), Art. T89 (publicidad), Art. T109.",
    datos: (d) => [["Versiones publicadas", d.impuestos.versiones.publicadas], ["Borradores", d.impuestos.versiones.borrador]] },
];

export default function Infraestructura() {
  const [d, setD] = useState<D | null>(null); const [err, setErr] = useState("");
  useEffect(() => { api("/api/admin/infra").then(setD).catch((e) => setErr(e.message)); }, []);
  return (<>
    <h1>Infraestructura de Placeta One</h1>
    <p style={{ color: "#555" }}>Plan 2027 · Grupo de La Placeta. Esta página explica cada parte del sistema, con su norma y un ejemplo, y muestra cómo está ahora mismo.</p>
    {err && <p role="alert" style={{ color: "#a33" }}>{err}</p>}
    <section style={box}>
      <h2 style={{ marginTop: 0 }}>Cómo circula el dinero y el impuesto</h2>
      <div style={{ display: "flex", flexWrap: "wrap", gap: 6, alignItems: "center", fontSize: 14 }}>
        {["Operación del cliente", "→", "Impuesto calculado con la norma", "→", "Recibo con certificado", "→", "Cobro automático", "→", "Cuenta destino (IBAN)"].map((t, i) =>
          <span key={i} style={t === "→" ? { color: "#888" } : { background: "#eef5ee", border: "1px solid #bcd9bc", borderRadius: 8, padding: "6px 10px" }}>{t}</span>)}
      </div>
      <p style={{ fontSize: 14, color: "#555", marginBottom: 0 }}>Aparte, el escaneo de IVA vigila las transferencias comerciales. Si una no tiene venta registrada, abre un hallazgo para que se revise y se regularice.</p>
    </section>
    <section style={box}>
      <h3 style={{ marginTop: 0 }}>Índice</h3>
      <div style={{ display: "flex", flexWrap: "wrap", gap: 8, fontSize: 14 }}>
        {TARJETAS.map((t) => <a key={t.id} href={`#${t.id}`}>{t.titulo}</a>)}
      </div>
    </section>
    {!d && !err && <p>Cargando datos…</p>}
    {TARJETAS.map((t) => (
      <section key={t.id} id={t.id} style={box}>
        <h2 style={{ marginTop: 0 }}>{t.titulo}</h2>
        <p>{t.resume}</p>
        <ul style={{ paddingLeft: 20 }}>{t.como.map((c) => <li key={c} style={{ marginBottom: 4 }}>{c}</li>)}</ul>
        <p style={{ background: "#f7f7f4", borderLeft: "3px solid #3a6", padding: "8px 12px" }}><b>Ejemplo.</b> {t.ejemplo}</p>
        <p><span style={chip}>📜 {t.norma}</span></p>
        {d && <div style={{ display: "flex", flexWrap: "wrap", gap: 10, marginTop: 8 }}>
          {t.datos(d).map(([k, v]) => <div key={k} style={{ border: "1px solid #ddd", borderRadius: 8, padding: "8px 12px", minWidth: 150 }}>
            <div style={{ fontSize: 12, color: "#777" }}>{k}</div><div style={{ fontSize: 18, fontWeight: 600 }}>{String(v)}</div></div>)}
        </div>}
        {d && t.barras && <Barras items={t.barras(d)} />}
        {t.ir && <p style={{ marginBottom: 0 }}><a href={t.ir.href}>{t.ir.texto} →</a></p>}
      </section>))}
  </>);
}
