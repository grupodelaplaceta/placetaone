import html, pathlib, json

E = lambda s: html.escape(str(s))
SEC = []                      # (id, título, cuerpo html)

def sec(id_, titulo, cuerpo):
    SEC.append((id_, titulo, cuerpo))

# ---------- Componentes gráficos (esquemas, dibujados en SVG) ----------
COL = {"p": ("#0b6", "#098a54", "#ffffff"),   # primario (verde)
       "s": ("#ffffff", "#888888", "#222222"), # secundario (blanco)
       "d": ("#b00000", "#8a0000", "#ffffff"), # peligro (rojo)
       "a": ("#f1f1f1", "#999999", "#222222")} # acción suave (gris)

def btn(t, k="p"):
    f, s, c = COL[k]
    w = max(96, int(len(t) * 7.6) + 34); h = 34
    return (f'<svg class="btn" width="{w}" height="{h}" viewBox="0 0 {w} {h}" xmlns="http://www.w3.org/2000/svg">'
            f'<rect x="1" y="1" width="{w-2}" height="{h-2}" rx="8" fill="{f}" stroke="{s}" stroke-width="1.5"/>'
            f'<text x="{w/2}" y="{h/2+5}" text-anchor="middle" font-family="Arial" font-size="13" font-weight="700" fill="{c}">{E(t)}</text></svg>')

def campo(ph, w=260):
    return (f'<svg class="campo" width="{w}" height="34" viewBox="0 0 {w} 34" xmlns="http://www.w3.org/2000/svg">'
            f'<rect x="1" y="1" width="{w-2}" height="32" rx="6" fill="#fff" stroke="#999"/>'
            f'<text x="10" y="22" font-family="Arial" font-size="12" fill="#888">{E(ph)}</text></svg>')

def campo_lleno(valor, w=260):
    return (f'<svg class="campo" width="{w}" height="34" viewBox="0 0 {w} 34" xmlns="http://www.w3.org/2000/svg">'
            f'<rect x="1" y="1" width="{w-2}" height="32" rx="6" fill="#fff" stroke="#555"/>'
            f'<text x="10" y="22" font-family="Arial" font-size="13" fill="#111">{E(valor)}</text></svg>')

def selector(valor, w=220):
    return (f'<svg class="campo" width="{w}" height="34" viewBox="0 0 {w} 34" xmlns="http://www.w3.org/2000/svg">'
            f'<rect x="1" y="1" width="{w-2}" height="32" rx="6" fill="#fff" stroke="#555"/>'
            f'<text x="10" y="22" font-family="Arial" font-size="13" fill="#111">{E(valor)}</text>'
            f'<path d="M{w-24} 14 L{w-14} 14 L{w-19} 21 Z" fill="#555"/></svg>')

def casilla(t, marcada=True):
    tick = '<path d="M4 11 L7 14 L13 6" stroke="#0b6" stroke-width="2.2" fill="none"/>' if marcada else ''
    w = 40 + int(len(t) * 6.4)
    return (f'<svg class="check" width="{w}" height="22" viewBox="0 0 {w} 22" xmlns="http://www.w3.org/2000/svg">'
            f'<rect x="1" y="3" width="15" height="15" rx="3" fill="#fff" stroke="#555"/>{tick}'
            f'<text x="24" y="15" font-family="Arial" font-size="12" fill="#222">{E(t)}</text></svg>')

def interruptor(on, t=""):
    f = "#0b6" if on else "#bbb"
    x = 30 if on else 4
    lab = "Activado" if on else "Desactivado"
    w = 130
    return (f'<svg class="switch" width="{w}" height="26" viewBox="0 0 {w} 26" xmlns="http://www.w3.org/2000/svg">'
            f'<rect x="1" y="3" width="52" height="22" rx="11" fill="{f}"/><circle cx="{x+11}" cy="14" r="9" fill="#fff"/>'
            f'<text x="66" y="18" font-family="Arial" font-size="12" fill="#222">{lab}</text></svg>')

def chip(t, c="#0b6"):
    w = max(64, int(len(t) * 7.2) + 22)
    return (f'<svg class="chip" width="{w}" height="22" viewBox="0 0 {w} 22" xmlns="http://www.w3.org/2000/svg">'
            f'<rect x="1" y="1" width="{w-2}" height="20" rx="10" fill="{c}"/>'
            f'<text x="{w/2}" y="15" text-anchor="middle" font-family="Arial" font-size="11" font-weight="700" fill="#fff">{E(t)}</text></svg>')

def barra(pct):
    w = 170
    return (f'<svg class="barra" width="{w}" height="14" viewBox="0 0 {w} 14" xmlns="http://www.w3.org/2000/svg">'
            f'<rect x="0" y="3" width="{w}" height="8" rx="4" fill="#e5e5e5"/>'
            f'<rect x="0" y="3" width="{w*pct/100:.0f}" height="8" rx="4" fill="#0b6"/></svg>')

def ventana(menu_activo, titulo, contenido, menu=None):
    if menu == []:
        return (f'<div class="ventana"><div class="barra-t"><span class="pt r"></span><span class="pt a"></span>'
                f'<span class="pt v"></span><span class="tit">Placeta One · {E(titulo)}</span></div>'
                f'<div class="cuerpo"><div class="main" style="min-height:120px">{contenido}</div></div></div>')
    menu = menu or ["Panel", "Estado", "Bancos", "Clientes", "Cuentas", "Productos", "Operaciones",
                    "Financiación", "Normas", "Disputas", "Fiscalidad", "Registros", "Personal", "API",
                    "Procesos", "Configuración", "Consola"]
    items = "".join(f'<div class="mi{" act" if m == menu_activo else ""}">{E(m)}</div>' for m in menu)
    return (f'<div class="ventana"><div class="barra-t"><span class="pt r"></span><span class="pt a"></span>'
            f'<span class="pt v"></span><span class="tit">Placeta One · {E(titulo)}</span></div>'
            f'<div class="cuerpo"><div class="side">{items}</div><div class="main">{contenido}</div></div></div>')

def tabla(cab, filas):
    h = "".join(f"<th>{E(c)}</th>" for c in cab)
    b = "".join("<tr>" + "".join(f"<td>{c}</td>" for c in f) + "</tr>" for f in filas)
    return f'<table class="t"><thead><tr>{h}</tr></thead><tbody>{b}</tbody></table>'

def pasos(lista):
    return '<ol class="pasos">' + "".join(f"<li>{p}</li>" for p in lista) + "</ol>"

def aviso(t, k="aviso"):
    etiqueta = {"aviso": "Aviso", "consejo": "Consejo", "peligro": "Cuidado", "error": "Si ves este error"}[k]
    return f'<div class="caja {k}"><b>{etiqueta}.</b> {t}</div>'

def ejemplo(titulo, intro, pasos_html, resultado):
    return (f'<div class="ejemplo"><div class="et">Ejemplo: {E(titulo)}</div><p>{intro}</p>{pasos(pasos_html)}'
            f'<p class="res"><b>Resultado esperado:</b> {resultado}</p></div>')

def fila_boton(descripcion, boton_html):
    return f'<div class="fb"><div class="fbd">{descripcion}</div><div class="fbb">{boton_html}</div></div>'

CSS = """
@page { size: A4; }
body { font-family: Arial, Helvetica, sans-serif; color:#1b1b1b; font-size: 10.5pt; line-height:1.45; margin:0; }
h1 { font-size: 26pt; color:#0b5d3b; margin: 0 0 6px; }
h2 { font-size: 17pt; color:#0b5d3b; border-bottom: 3px solid #0b6; padding-bottom:4px; margin-top:0; page-break-before: always; }
h3 { font-size: 13pt; color:#0b5d3b; margin: 18px 0 6px; page-break-after: avoid; }
h4 { font-size: 11pt; margin: 12px 0 4px; page-break-after: avoid; }
p { margin: 6px 0; }
.portada { height: 250mm; display:flex; flex-direction:column; justify-content:center; page-break-after: always; }
.portada .sub { font-size: 14pt; color:#555; margin-top:10px; }
.portada .pie { margin-top:auto; font-size:9pt; color:#777; }
.indice ol { columns: 2; font-size: 10pt; }
.caja { border-radius:8px; padding:8px 12px; margin:10px 0; border-left: 5px solid; page-break-inside: avoid; }
.caja.aviso { background:#fff8e1; border-color:#e0a800; }
.caja.consejo { background:#e8f7ef; border-color:#0b6; }
.caja.peligro { background:#fdecec; border-color:#b00; }
.caja.error { background:#f1f1ff; border-color:#4650c8; }
.ejemplo { background:#f6f9fc; border:1px solid #cfd9e6; border-radius:10px; padding:10px 14px; margin:12px 0; page-break-inside: avoid; }
.ejemplo .et { font-weight:700; color:#1d4f91; margin-bottom:4px; }
.ejemplo .res { background:#e8f7ef; border-radius:6px; padding:6px 10px; }
.pasos { padding-left: 20px; }
.pasos li { margin: 4px 0; }
table.t { width:100%; border-collapse: collapse; font-size: 9.5pt; margin: 8px 0; page-break-inside: auto; }
table.t th { background:#0b5d3b; color:#fff; text-align:left; padding:5px 7px; }
table.t td { border-bottom:1px solid #ddd; padding:5px 7px; vertical-align: top; }
table.t tr { page-break-inside: avoid; }
.ventana { border:1px solid #888; border-radius:8px; overflow:hidden; margin:10px 0; page-break-inside: avoid; background:#fff; }
.barra-t { background:#e9e9e9; padding:5px 8px; display:flex; align-items:center; gap:5px; border-bottom:1px solid #bbb; }
.pt { width:9px; height:9px; border-radius:50%; display:inline-block; }
.pt.r { background:#ff5f57; } .pt.a { background:#febc2e; } .pt.v { background:#28c840; }
.tit { margin-left:8px; font-size:9pt; color:#444; }
.cuerpo { display:flex; min-height: 150px; }
.side { width: 150px; background:#0b5d3b; color:#e8f5ee; font-size:8.5pt; padding:6px 0; }
.side .mi { padding:4px 12px; }
.side .mi.act { background:#0b6; color:#fff; font-weight:700; }
.main { flex:1; padding:10px 12px; font-size:9pt; }
.fb { display:flex; align-items:center; gap:14px; border:1px solid #e0e0e0; border-radius:8px; padding:8px 10px; margin:6px 0; page-break-inside: avoid; }
.fb .fbd { flex:1; font-size:9.5pt; }
.fb .fbb { flex:0 0 auto; }
.leyenda { display:flex; gap:12px; flex-wrap:wrap; font-size:9pt; color:#444; margin:6px 0; }
.glos dt { font-weight:700; margin-top:6px; }
.glos dd { margin:0 0 4px 16px; }
.nota-mock { font-size:8.5pt; color:#666; font-style:italic; margin-top:2px; }
.check-lista li { list-style: none; margin:3px 0; }
.check-lista li:before { content:"☐ "; font-size:12pt; }
"""

def ver_leyenda():
    return ('<div class="leyenda">' + btn("Botón principal", "p") + btn("Botón secundario", "s") +
            btn("Acción peligrosa", "d") + btn("Acción suave", "a") + "</div>"
            '<p class="nota-mock">Los dibujos son esquemas para orientarte. Los nombres de los botones son los del código; el aspecto exacto puede variar.</p>')

# ============================ SECCIONES ============================
sec("1", "1. Antes de empezar", f"""
<h3>Qué es Placeta One</h3>
<p>Es el sistema bancario interno del Grupo de La Placeta. Todo el dinero se mide en <b>Placetas (Pz)</b>.
Maneja cuentas, pagos, la RBU (renta básica), subvenciones y bonos, empresas con su organigrama y su nómina,
y las finanzas institucionales.</p>

<h3>Quién hace qué</h3>
{tabla(["Rol","Qué puede hacer","Dónde lo hace"], [
 ["<b>Junta (administrador)</b>","Todo lo del sistema: ajustes, impuestos, productos, subvenciones, convocatorias de empresa, incidencias graves","Panel de administración"],
 ["<b>Personal</b>","Acceso al panel según su rol. Hoy, en la práctica, solo la Junta entra","Panel"],
 ["<b>Entidad (banco)</b>","Sus clientes, cuentas, empresas, pasarela y programas. <b>Solo ve los de su entidad</b>","API de banca"],
 ["<b>Titular de empresa</b>","Organigrama, cuentas, complementos, nómina y convocatorias de su empresa","API de banca, identificado con su DIP"],
 ["<b>Usuario</b>","Su cuenta, transferencias, bonos RBU, deudas y sus datos","App y API del usuario"],
])}

<h3>Tres palabras que vas a ver todo el rato</h3>
<dl class="glos">
<dt>DIP</dt><dd>Identificador de una persona (por ejemplo, <code>DIP-23749931M</code>). Las acciones de empresa se firman con el DIP del titular.</dd>
<dt>CIP</dt><dd>Identificador de una entidad institucional (por ejemplo, <code>CIP-00000004</code>). Cada empresa tiene el suyo, y se crea sola al añadirle su primera cuenta.</dd>
<dt>Doble firma</dt><dd>Algunas acciones necesitan que <b>otra persona</b> las apruebe. Nadie aprueba su propio cambio, ni siquiera la Junta.</dd>
<dt>Reserva</dt><dd>Dinero bloqueado para una subvención o convocatoria. No se puede gastar hasta que se paga o caduca.</dd>
</dl>

<h3>Dos entornos</h3>
<p><b>Pruebas</b> sirve para ensayar: aquí se puede equivocar uno sin consecuencias. <b>Producción</b> tiene dinero real.
Regla de oro: <b>cualquier tarea nueva, primero en pruebas</b>.</p>
{aviso("Esta guía describe lo que hace el código. Las pantallas todavía no se han probado en un navegador real en un entorno de producción. Si algo no coincide con lo que ves, anótalo y avísanos.")}

<h3>Cómo leer los dibujos</h3>
<p>Los botones dibujados en esta guía tienen el mismo nombre que en el sistema. El color indica su peso:</p>
{ver_leyenda()}
""")

sec("2", "2. Primeros pasos", f"""
<h3>2.1 Entrar en el panel</h3>
<p>Abre la dirección del panel de administración. Verás un formulario sencillo con dos campos y un botón.</p>
{ventana("Panel", "Entrar", '<div style="padding:18px"><b>Email</b><br>' + campo("tu@laplaceta.org", 280) + '<br><br><b>Contraseña</b><br>' + campo("••••••••", 280) + '<br><br>' + btn("Entrar", "p") + '</div>', menu=[])}
{pasos([
 "Escribe tu <b>email de personal</b>.",
 "Escribe tu <b>contraseña</b>.",
 "Pulsa <b>Entrar</b>. Si la contraseña es incorrecta, aparece un aviso en rojo debajo del formulario.",
])}
{aviso("Si olvidas la contraseña, avisa a la Junta para que la restablezca. ", "consejo")}

<h3>2.2 Moverte por el menú</h3>
<p>El menú lateral agrupa todas las secciones. La sección en la que estás aparece resaltada en verde.</p>
{ventana("Financiación", "Financiación", '<b>Subvenciones, bonos y tesorería</b><br><span class="nota-mock">Pantalla de ejemplo: el menú lateral resalta la sección actual.</span>')}
{tabla(["Sección","Para qué sirve"], [
 ["Panel","Resumen del día: previsiones, avisos y accesos rápidos"],
 ["Estado","Salud del sistema. Si aparece un problema crítico, mírala primero"],
 ["Operaciones / Registros","Qué ha pasado: movimientos y auditoría (quién hizo qué, cuándo y por qué)"],
 ["Financiación / Convocatorias de empresa","Subvenciones, bonos, concesiones y reversiones"],
 ["Productos / Normas / Fiscalidad","Qué se contrata, qué topes aplican y qué impuestos hay"],
 ["Configuración","Ajustes del sistema y creación de impuestos"],
 ["Consola / API","Herramientas técnicas: úsalas solo si sabes lo que haces, y mejor en pruebas"],
])}

<h3>2.3 Leer una tabla</h3>
<p>Casi todas las pantallas son tablas. Cada fila es un elemento (una convocatoria, una concesión, un producto…). Los colores de las etiquetas te dicen el estado de un vistazo.</p>
{tabla(["Nombre","Estado","Pagado / concedido","Acciones"], [
 ["Bono cultura 2027", chip("abierta"), barra(40) + " 200 / 500 Pz", btn("Cerrar","s") + " " + btn("Concesiones (2)","a")],
 ["Ayuda limpieza", chip("cerrada","#888"), barra(100) + " 300 / 300 Pz", btn("Concesiones (4)","a")],
])}
{aviso("Un botón que no aparece no está roto: la acción no está permitida en el estado actual de ese elemento. Por ejemplo, no verás «Cerrar» en una convocatoria que ya está cerrada.", "consejo")}

<h3>2.4 Buscar, filtrar y actualizar</h3>
{pasos([
 "Escribe en la caja de <b>Buscar…</b> (arriba). Filtra por nombre o por clave, según la pantalla.",
 "Usa los <b>selectores de estado, origen o ámbito</b> para acotar. Por ejemplo, «Solo empresas» oculta las convocatorias de la Junta.",
 "Si los datos parecen antiguos, pulsa <b>Actualizar</b> o <b>Reintentar</b>.",
])}

<h3>2.5 Mensajes: qué significan los colores</h3>
{tabla(["Aspecto","Significado","Qué hacer"], [
 ["Texto en verde o mensaje de éxito","La acción se ha hecho","Nada. Comprueba el resultado en la tabla"],
 ["Texto en rojo o aviso de error","La acción no se ha hecho","Lee el mensaje; la tabla de errores (sección 13) lo explica"],
 ["«No se ha podido cargar» + <b>Reintentar</b>","La pantalla no ha podido leer sus datos","Pulsa Reintentar. Si vuelve a salir, copia el texto y avísanos"],
 ["Badge <b>🔒 2ª persona</b>","Ese ajuste necesita aprobación de otra persona","Propón el cambio y pide la aprobación"],
])}
{aviso("Nunca repitas una operación de dinero varias veces seguidas porque «no ha funcionado». Antes, mira en Registros si ya se hizo. Ver sección 12 (incidencias).", "peligro")}

<h3>2.6 Salir</h3>
<p>Pulsa <b>Salir</b> al final del menú cuando termines, sobre todo en un equipo compartido.</p>
""")

sec("3", "3. Mapa de botones", f"""
<p>Esta tabla resume los botones que más usarás. Cada botón hace exactamente lo que dice; si su acción es peligrosa, lo verás marcado en rojo.</p>
{tabla(["Pantalla","Botón","Qué hace","Peso"], [
 ["Configuración · Ajustes", btn("Proponer cambio","p"), "Envía el cambio para que otra persona lo apruebe", "Principal"],
 ["Configuración · Pendientes", btn("Aprobar","p") + " " + btn("Rechazar","s"), "Aprueba o rechaza un cambio pendiente", "Principal / secundario"],
 ["Configuración · Nuevo impuesto", btn("Crear como borrador","p"), "Crea el impuesto y su versión sin publicarla", "Principal"],
 ["Productos", btn("Aprobar y activar","p"), "Pasa un borrador a activo", "Principal"],
 ["Productos", btn("Retirar","s"), "El producto deja de ofrecerse", "Secundario"],
 ["Financiación · Concesiones", btn("+ Nueva concesión","p"), "Abre el formulario para conceder y reservar", "Principal"],
 ["Financiación · Concesiones", btn("Informe PDF","s"), "Descarga el informe de justificación", "Secundario"],
 ["Financiación · Concesiones", btn("Revertir…","d"), "Revierte un abono (pide el motivo)", "Peligroso"],
 ["Financiación · Justificaciones", btn("Aprobar y pagar","p") + " " + btn("Rechazar","s"), "Paga lo justificado o lo rechaza", "Principal / secundario"],
 ["Convocatorias de empresa", btn("Cerrar","d"), "Ya no admite concesiones nuevas (pide confirmación)", "Peligroso"],
 ["Convocatorias de empresa", btn("Concesiones (n)","a"), "Despliega la lista de beneficiarios", "Suave"],
 ["Cualquier tabla", btn("Reintentar","s"), "Vuelve a cargar los datos", "Secundario"],
])}
{aviso("Los botones rojos son irreversibles o afectan a dinero. Antes de pulsarlos, lee el mensaje de confirmación y comprueba el elemento sobre el que actúan.", "peligro")}
""")

sec("4", "4. Junta: Configuración (ajustes)", f"""
<p>Los ajustes controlan límites, plazos y topes (por ejemplo, el importe semanal de la RBU o el plazo de disputa). <b>Ningún ajuste se cambia directamente.</b> Se propone, y otra persona lo aprueba.</p>

<h3>4.1 Dónde está cada cosa</h3>
{ventana("Configuración", "Configuración · Ajustes", f'''
<div style="display:flex;gap:8px;align-items:center;margin-bottom:6px">{campo("Buscar ajuste…", 200)} {selector("Global", 130)}</div>
<div style="display:flex;gap:6px;flex-wrap:wrap;margin-bottom:8px">{chip("Todas","#555")} {chip("RBU y bienestar","#0b6")} {chip("Cuentas","#0b6")}</div>
<div style="border-top:1px solid #eee;padding:6px 0"><b>Límite diario por defecto</b> {chip("🔒 2ª persona","#8a5a00")}<br>
<span class="nota-mock">default_daily_limit · actual: 0</span><br>{campo_lleno("0", 90)} </div>''')}
<div class="nota-mock">Dibujo: se busca el ajuste, se cambia su valor y aparece el campo «Motivo».</div>

<h3>4.2 Cambiar un ajuste (paso a paso)</h3>
{pasos([
 "Entra en <b>Configuración → Ajustes</b>.",
 "Busca el ajuste con la caja <b>Buscar ajuste…</b>, o elige su categoría (RBU y bienestar, Cuentas, Fiscalidad…).",
 "Cambia el valor con su control: un <b>interruptor</b> para sí/no, un <b>selector</b> si hay opciones cerradas, o un <b>número</b> (verás su rango).",
 "Aparece el campo <b>Motivo (obligatorio)</b>. Escribe por qué cambias el valor (mínimo 5 caracteres).",
 "Pulsa <b>Proponer cambio</b>. El ajuste queda <b>pendiente</b>. No cambia todavía.",
 "Otra persona entra en el bloque <b>Pendientes de aprobación</b> y pulsa <b>Aprobar</b> (o <b>Rechazar</b>).",
])}
<div class="fb"><div class="fbd"><b>Pendientes de aprobación</b><br><span class="nota-mock">default_daily_limit: 0 → 500 · «Límite diario, pedido por Operaciones»</span></div><div class="fbb">{btn("Aprobar","p")} {btn("Rechazar","s")}</div></div>

<h3>4.3 Ámbito: global o por entidad</h3>
<p>Arriba, en <b>Ámbito</b>, eliges <b>Global</b> o una entidad concreta. Algunos ajustes solo se cambian en Global: si eliges una entidad, aparecen deshabilitados y ponen «Solo se cambia en el ámbito global». Eso es intencionado.</p>

{ejemplo("Subir el límite diario por defecto de las cuentas",
 "La Junta quiere pasar el límite diario por defecto de 0 (sin límite) a 500 Pz, por motivos de control.",
 ["Entra en <b>Configuración → Ajustes</b> y busca <i>límite diario</i>.",
  "Pon el <b>ámbito en Global</b> (arriba a la derecha).",
  "Cambia el valor a <b>500</b>.",
  "Escribe el motivo: <i>Control de riesgo por cuenta, decisión de la Junta del día 21/11.</i>",
  "Pulsa <b>Proponer cambio</b>.",
  "Una segunda persona de la Junta abre <b>Pendientes de aprobación</b> y pulsa <b>Aprobar</b>."],
 "El valor pasa a 500 Pz. Queda constancia en Registros con el motivo y las dos personas.")}

{aviso("Quien propone un cambio <b>no puede aprobarlo</b>. Si intentas aprobar tu propio cambio, el sistema responde: «El proponente no puede aprobar su propio cambio». Pide a otra persona que lo haga.", "error")}
{aviso("Rechazar un cambio no lo borra: queda registrado como rechazado, con quién lo rechazó.", "consejo")}
""")

sec("5", "5. Junta: crear un impuesto", f"""
<p>El asistente de impuestos tiene <b>cuatro pasos</b>. Puedes volver atrás en cualquier momento, y nada entra en vigor hasta que otra persona lo publica.</p>

<h3>Paso 1: el impuesto</h3>
{ventana("Configuración", "Configuración · Nuevo impuesto", f'''
<div style="display:flex;gap:6px;margin-bottom:10px">{btn("1. Impuesto","p")} {btn("2. Cómo se cobra","s")} {btn("3. Vigencia","s")} {btn("4. Revisar","s")}</div>
<b>Norma existente</b><br>{selector("— nueva norma —", 260)}<br><br>
<b>Código</b> {campo("IVA", 90)} &nbsp; <b>Nombre</b> {campo("Impuesto sobre el valor añadido", 240)}<br><br>
<b>Límite central (%)</b> {campo("21", 80)} &nbsp; <b>Cuenta recaudadora</b> {selector("ES12 · Recaudación", 200)}<br><br>
<div style="text-align:right">{btn("Siguiente →","p")}</div>''')}
{pasos([
 "Si el impuesto ya tiene norma, elígela en <b>Norma existente</b>. Si no, deja «nueva norma».",
 "Rellena el <b>código</b>: de 2 a 10 letras mayúsculas, números o guion bajo (por ejemplo <code>IVA</code>).",
 "Escribe el <b>nombre</b> y el <b>límite central (%)</b>: es el tope que nadie puede superar.",
 "Elige la <b>cuenta recaudadora</b>: a donde va el dinero del impuesto.",
])}

<h3>Paso 2: cómo se cobra</h3>
{ventana("Configuración", "Cómo se cobra", f'''
<div style="margin-bottom:8px">{btn("Porcentaje","p")} &nbsp; {btn("Importe fijo","s")}</div>
<b>Porcentaje (%)</b> {campo_lleno("21", 80)} &nbsp; <b>Mínimo (Pz)</b> {campo("opcional", 100)} &nbsp; <b>Máximo (Pz)</b> {campo("opcional", 100)}
<div style="margin-top:10px;background:#f5f8ff;padding:8px;border-radius:6px"><b>Vista previa:</b> Se cobrará el 21 % de cada operación afectada.<br><span class="nota-mock">Ejemplo: una operación de 100 Pz pagaría 21,00 Pz.</span></div>''')}
{pasos([
 "Elige <b>Porcentaje</b> (un % de cada operación) o <b>Importe fijo</b> (una cantidad en Pz por operación).",
 "Rellena el valor. El mínimo y el máximo son opcionales.",
 "<b>Revisa la vista previa</b>: es exactamente lo que se cobrará. Si no lo entiendes, no sigas.",
])}

<h3>Paso 3: vigencia y alcance</h3>
{ventana("Configuración", "Vigencia y alcance", f'''
<b>Entra en vigor</b> {campo_lleno("2027-01-01", 130)} &nbsp; <b>Fin (opcional)</b> {campo("", 130)}<br><br>
<b>Entidad</b> {selector("Todas las entidades", 200)}<br><br>
<b>Operaciones anteriores a la entrada en vigor</b><br>
<div style="margin:6px 0">{btn("No aplicar","p")} &nbsp; {btn("Solo simular","s")} &nbsp; {btn("Aplicar automáticamente","s")}</div>
<b>Motivo y norma que lo justifica</b><br>{campo("Norma T-21, aprobada por la Junta…", 420)}''')}
{tabla(["Opción","Qué significa","Cuándo usarla"], [
 ["<b>No aplicar</b>","Solo afecta a operaciones desde la entrada en vigor","Lo normal"],
 ["<b>Solo simular</b>","Calcula el efecto sobre el pasado, sin cobrar nada","Para ver el impacto antes de decidir"],
 ["<b>Aplicar automáticamente</b>","Cobra también sobre operaciones pasadas","Solo si la Junta lo ha decidido expresamente"],
])}

<h3>Paso 4: revisar y crear</h3>
{pasos([
 "Revisa el resumen: nombre, frase de lo que se cobra, ejemplo y vigencia.",
 "Pulsa <b>Crear como borrador</b>. Se crea, pero <b>todavía no está en vigor</b>.",
 "Otra persona de <b>Fiscal</b> entra en la versión y pulsa <b>Publicar</b>. Quien la redactó no puede publicarla.",
])}
{ejemplo("Crear el IVA al 21 %",
 "La Junta crea el IVA general, aplicable desde el 1 de enero de 2027 a todas las entidades, sin retroactividad.",
 ["Paso 1: código <code>IVA</code>, nombre «Impuesto sobre el valor añadido», límite 21 %, cuenta recaudadora de la Junta.",
  "Paso 2: Porcentaje, valor 21.",
  "Paso 3: entra en vigor 2027-01-01, sin fin, entidad «Todas», <b>No aplicar</b> a operaciones anteriores, motivo «Norma T-21 aprobada por la Junta».",
  "Paso 4: <b>Crear como borrador</b>. Una persona distinta de quien la creó pulsa <b>Publicar</b>."],
 "La versión queda publicada y entra en vigor el 1 de enero de 2027. Antes de esa fecha, sigue sin aplicarse.")}
{aviso("Si te sale «Publicar exige un aprobador distinto del autor», es lo correcto: pide a otra persona de Fiscal que la publique.", "error")}
""")

sec("6", "6. Junta: productos", f"""
<p>Un producto es lo que se contrata: una cuenta, una tarjeta, una membresía. Cada producto tiene un <b>estado</b>: <b>borrador</b>, <b>activo</b> o <b>retirado</b>.</p>

<h3>6.1 Crear un producto</h3>
{ventana("Productos", "Productos · Nuevo", f'''
<b>Código</b> {campo("CTA-PERS", 140)} &nbsp; <b>Nombre</b> {campo("Cuenta personal", 220)}<br><br>
<b>Tipo</b> {selector("Cuenta personal", 180)} &nbsp; <b>Límite diario (Pz)</b> {campo("0", 90)}<br><br>
{casilla("Aprobación automática", True)}<br>
<span class="nota-mock">Si la marcas, el producto se activa al guardarlo, sin revisión manual.</span><br><br>
{btn("Guardar","p")} &nbsp; {btn("Cancelar","s")}''')}
{pasos([
 "Entra en <b>Productos</b> y pulsa el botón de alta.",
 "Rellena código, nombre, tipo, límites y fechas de validez.",
 "Decide si quieres <b>Aprobación automática</b>. Si la dejas sin marcar, el producto queda en <b>borrador</b>.",
 "Pulsa <b>Guardar</b>.",
])}

<h3>6.2 Activar un producto</h3>
<div class="fb"><div class="fbd"><b>Aprobar y activar</b>: pasa un borrador a activo. Queda registrado quién lo aprobó.</div><div class="fbb">{btn("Aprobar y activar","p")}</div></div>
<div class="fb"><div class="fbd"><b>Activar aprobación automática</b>: cambia la marca en un producto existente. Si está en borrador, se activa de inmediato.</div><div class="fbb">{btn("Activar aprobación automática","a")}</div></div>
<div class="fb"><div class="fbd"><b>Retirar</b>: deja de ofrecerse. <b>Descartar</b>: borra un borrador que no se va a usar.</div><div class="fbb">{btn("Retirar","s")} {btn("Descartar","d")}</div></div>

{ejemplo("Dar de alta una cuenta personal con aprobación automática",
 "La Junta quiere que la cuenta personal básica se pueda contratar sin revisión manual.",
 ["Entra en <b>Productos → Nuevo</b>.",
  "Código <code>CTA-PERS</code>, nombre «Cuenta personal», tipo «Cuenta personal».",
  "Marca <b>Aprobación automática</b>.",
  "Pulsa <b>Guardar</b>."],
 "El producto aparece como <b>activo</b> en la tabla, con la columna «Auto» marcada. No necesita aprobación manual.")}
{aviso("Quitar la aprobación automática no desactiva el producto: solo significa que, en adelante, habrá que aprobarlo a mano. Para desactivarlo, usa <b>Retirar</b>.", "consejo")}
""")

sec("7", "7. Junta: subvenciones y bonos", f"""
<p>Esta es la pantalla que más cuidado merece, porque mueve dinero público. El flujo tiene <b>cinco pasos</b>, y la pantalla los muestra arriba del todo:</p>
{tabla(["Paso","Qué es","Qué pasa con el dinero"], [
 ["1. Programa","El marco de la ayuda: presupuesto y cuenta de fondos","Ninguno todavía"],
 ["2. Concesión","Reserva el importe para el beneficiario","<b>Se reserva</b>. Si no hay fondos, no se crea"],
 ["3. Justificación","El beneficiario presenta un gasto de su cuenta","Ninguno: solo se revisa"],
 ["4. Abono","Se paga lo justificado","<b>Sale</b> de la reserva hacia el beneficiario"],
 ["5. Caducidad o reversión","Lo no usado caduca; un abono se puede revertir","<b>Se libera</b> la reserva, o vuelve el dinero"],
])}

<h3>7.1 Conceder una subvención o bono</h3>
{ventana("Financiación", "Financiación · Concesiones", f'''
<div style="display:flex;justify-content:space-between;align-items:center"><b>Concesiones</b> {btn("+ Nueva concesión","p")}</div>
<div style="margin-top:8px;background:#f8fafc;padding:8px;border-radius:6px">
<b>Programa</b> {selector("Ayuda limpieza (subvención)", 250)} &nbsp; <b>Beneficiario</b> {selector("Cuenta de Ana · ES12…", 220)}<br><br>
<b>Importe (Pz)</b> {campo_lleno("300", 90)} &nbsp; <b>Convocatoria</b> {selector("Sin convocatoria", 160)} &nbsp; <b>Caduca</b> {campo("opcional", 110)}<br><br>
{btn("Conceder y reservar","p")}</div>''')}
{pasos([
 "En <b>Financiación → Concesiones</b>, pulsa <b>+ Nueva concesión</b>.",
 "Elige el <b>programa</b>, el <b>beneficiario</b> (su cuenta) y el <b>importe</b> en Pz.",
 "Opcional: elige una <b>convocatoria</b>. Si la eliges, hereda su caducidad.",
 "<b>Caduca</b> es obligatoria en los <b>bonos</b>. Debe ser posterior a hoy.",
 "Pulsa <b>Conceder y reservar</b>.",
])}
{aviso("Si el sistema dice «Supera el presupuesto» o «Sin fondos suficientes», <b>no se ha concedido nada</b>. Reduce el importe o revisa el saldo del programa.", "error")}

<h3>7.2 Justificar y pagar un gasto</h3>
{pasos([
 "En <b>Justificaciones y abonos</b>, pulsa crear.",
 "Elige la <b>concesión</b>, la <b>transacción</b> del beneficiario que justifica el gasto, el <b>número de factura</b> y el <b>importe</b>.",
 "La justificación queda <b>pendiente</b>.",
 "Pulsa <b>Aprobar y pagar</b> para abonarla. El abono consume la reserva.",
 "Si no procede, pulsa <b>Rechazar</b>.",
])}
<div class="fb"><div class="fbd"><b>Aprobar y pagar</b>: paga el importe justificado al beneficiario.</div><div class="fbb">{btn("Aprobar y pagar","p")} {btn("Rechazar","s")}</div></div>

<h3>7.3 Revertir un abono</h3>
<p>Úsalo solo si se detecta una infracción o un incumplimiento de requisitos. Es irreversible para el programa, así que pide siempre el motivo por escrito.</p>
{pasos([
 "En la tabla de <b>Concesiones</b>, localiza la concesión afectada y pulsa <b>Revertir…</b>.",
 "Escribe el <b>motivo</b> (mínimo 10 caracteres). Quedará en Registros.",
 "El sistema decide solo, según el saldo del beneficiario:",
])}
{tabla(["Situación","Qué pasa"], [
 ["El beneficiario <b>tiene saldo</b>","El abono se revierte entero. El dinero vuelve al programa"],
 ["El beneficiario <b>no tiene saldo suficiente</b>","Lo disponible vuelve de inmediato y lo que falta queda como <b>deuda</b>, que se cobra cuando tenga fondos. <b>Nunca queda saldo negativo.</b>"],
])}
{ejemplo("Revertir 120 Pz por un gasto no elegible",
 "Una subvención pagó 120 Pz por un gasto que resulta no elegible. El beneficiario ha gastado 40 Pz del abono.",
 ["Localiza la concesión y pulsa <b>Revertir…</b>.",
  "Escribe el motivo: <i>Gasto no elegible según la bases, factura 2027/014.</i>",
  "Confirma."],
 "El beneficiario tiene 80 Pz disponibles: se devuelven 80 Pz al programa y quedan 40 Pz como <b>deuda</b> de su cuenta. La justificación queda rechazada, así que no se puede volver a pagar.")}

<h3>7.4 Informe de justificación</h3>
<div class="fb"><div class="fbd"><b>Informe PDF</b>: un resumen por concesión, con concedido, aprobado, pagado, pendiente, justificaciones y reversiones.</div><div class="fbb">{btn("Informe PDF","s")}</div></div>
<p>Úsalo para el expediente. Si el informe sale con filas que no esperas, compara con Registros antes de dar nada por bueno.</p>

<h3>7.5 Caducidad y reautorización por convocatoria</h3>
{ventana("Financiación", "Convocatorias · caducidad", f'''
<table class="t"><tr><th>Nombre</th><th>Caducidad de bonos</th><th>Recuperados</th></tr>
<tr><td>Bono cultura 2027</td><td>{campo_lleno("2027-09-30", 120)} {btn("Guardar","s")}</td><td>{casilla("reautorizar lo recuperado", True)}</td></tr></table>''')}
<ul>
<li><b>Caducidad de bonos:</b> escribe la fecha y pulsa <b>Guardar</b>. Aplica a los bonos <i>nuevos</i> de esa convocatoria.</li>
<li><b>Reautorizar lo recuperado:</b> si está marcada, lo que se cobre de una deuda por reversión vuelve a quedar reservado, siempre que la subvención siga activa, sin caducar y la convocatoria esté abierta.</li>
</ul>
""")

sec("8", "8. Junta: convocatorias de empresa", f"""
<p>Las empresas pueden <b>convocar</b> subvenciones y bonos, abiertos a toda la entidad o dirigidos a una empresa concreta. Como Junta, aquí las <b>supervisas</b>.</p>
{ventana("Convocatorias de empresa", "Convocatorias de empresa", f'''
<div style="display:flex;gap:10px;margin-bottom:8px">{selector("Estado: Todas", 140)} {selector("Origen: Solo empresas", 170)} {btn("Actualizar","s")}</div>
<table class="t"><tr><th>Convocatoria</th><th>Empresa</th><th>Destino</th><th>Concedido</th><th>Estado</th><th></th></tr>
<tr><td><b>Bono cultura 2027</b></td><td>Ejemplo v2</td><td>Toda la entidad</td><td>{barra(40)} 200 / 500 Pz</td><td>{chip("abierta")}</td><td>{btn("Cerrar","d")} {btn("Concesiones (2)","a")}</td></tr></table>''')}
{pasos([
 "Entra en <b>Convocatorias de empresa</b>.",
 "Revisa la empresa, el destino, la cuenta de fondos y lo concedido frente al importe.",
 "Para ver a quién se ha concedido, pulsa <b>Concesiones (n)</b>.",
 "Para cerrar una convocatoria, pulsa <b>Cerrar</b>. El sistema pide confirmación.",
])}
{ejemplo("Cerrar una convocatoria que ya ha alcanzado su objetivo",
 "La convocatoria «Bono cultura 2027» tiene 500 Pz y ya se han concedido 500 Pz.",
 ["Pulsa <b>Concesiones (n)</b> para comprobar que están todas bien.",
  "Pulsa <b>Cerrar</b>.",
  "Confirma en el aviso: «¿Cerrar «Bono cultura 2027»? No admitirá concesiones nuevas».",],
 "La convocatoria pasa a <b>cerrada</b>. Lo ya concedido sigue su curso, pero no se pueden hacer concesiones nuevas.")}
{aviso("Cerrar es <b>definitivo para nuevas concesiones</b>: si luego necesitas más, hay que abrir otra convocatoria. Por eso el botón es rojo.", "peligro")}
""")

sec("9", "9. Junta: otras secciones", f"""
<h3>Estado</h3>
<p>Muestra la salud del sistema. Si aparece un <b>problema crítico</b>, es lo primero que hay que mirar, antes que cualquier otra cosa. Usa el botón de comprobación para volver a revisar.</p>
{ventana("Estado", "Estado", '<p><b>✓ Sin problemas críticos</b> &nbsp; ' + btn("Comprobar","s") + '</p><p><b>⚠ 1 problema crítico</b>: <span class="nota-mock">mira el detalle antes de cualquier operación de dinero</span></p>')}

<h3>Registros</h3>
<p>Es la <b>auditoría</b>: cada acción importante, con su autor, su fecha y su motivo. Úsala siempre antes de investigar nada o de repetir una operación que pudo fallar.</p>

<h3>Disputas, Normas y Fiscalidad</h3>
<ul>
<li><b>Disputas:</b> una deuda se puede disputar dentro de su plazo (60 días desde el vencimiento, y solo hasta lo pagado). Una disputa de más de <b>1.000 Pz</b> necesita dos personas distintas para resolverla.</li>
<li><b>Normas:</b> topes y normas. Cambiar un tope es un ajuste y sigue la doble firma.</li>
<li><b>Fiscalidad:</b> impuestos y versiones publicadas. Las versiones se redactan como borrador y las publica otra persona.</li>
</ul>

<h3>Personal</h3>
<p>Quién tiene acceso al panel y con qué rol. Dar de alta o quitar personal es una acción sensible: pide a otra persona de la Junta que la revise.</p>

<h3>Consola y API</h3>
{aviso("La <b>Consola</b> ejecuta operaciones técnicas directamente sobre el sistema. Un error aquí puede afectar a muchos datos a la vez. Úsala solo con una persona técnica al lado, y prueba primero en pruebas.", "peligro")}
""")

sec("10", "10. Entidades: la API de banca", f"""
<p>Una entidad (banco) opera por la <b>API de banca</b>. Ve y gestiona <b>solo sus propios</b> clientes, cuentas, empresas y programas. Las rutas exactas, sus parámetros y ejemplos están en <code>docs/openapi.json</code>; aquí tienes lo básico.</p>

<h3>10.1 Antes de llamar a la API</h3>
{pasos([
 "La Junta te da una <b>clave de cliente</b> (identificador y secreto). El secreto se guarda <b>solo en tu servidor</b>, nunca en una web ni en el código que se comparte.",
 "Cada llamada se <b>firma</b> con el secreto de firma de tu cliente, para que el sistema compruebe que la petición es tuya y no se ha alterado.",
 "Cada petición lleva una <b>fecha</b> y un <b>identificador de un solo uso</b>: una petición repetida se rechaza.",
 "Prueba siempre contra el entorno de <b>pruebas</b> antes de pasar a producción.",
])}
{aviso("Si sospechas que una clave o un secreto se ha filtrado, <b>rótala</b> desde la propia API (rotar clave) y avisa a la Junta de inmediato. No esperes a tener certeza.", "peligro")}

<h3>10.2 Ejemplo básico: dar de alta una empresa con su cuenta</h3>
<p>Una empresa nueva se crea desde la entidad. Su primera cuenta de empresa crea <b>automáticamente</b> su entidad institucional (su CIP) y su organigrama inicial.</p>
{pasos([
 "Da de alta la empresa con su nombre y su identificador fiscal.",
 "Añade su <b>primera cuenta de empresa</b>: <code>POST /api/v1/bk/empresas/&#123;id&#125;/cuentas</code> con el IBAN. Eso crea su CIP.",
 "Comprueba en la ficha de la empresa que aparece el <b>CIP</b> y el organigrama inicial (Junta, puesto de titular y titular nombrado).",
])}
<div class="ejemplo"><div class="et">Cuerpo de la petición: añadir una cuenta</div><pre>{{ "iban": "PZ-0000-0007" }}</pre>
<p class="res"><b>Resultado esperado:</b> la cuenta queda vinculada y la empresa tiene CIP. Si la entidad no se ha creado, la ficha muestra el último error automático, que es lo primero que debes copiar si avisas.</p></div>
{aviso("Si la empresa no tiene CIP tras añadir la cuenta, <b>no lo repitas</b> sin mirar primero la ficha: el último error está ahí.", "error")}

<h3>10.3 Ejemplo básico: crear un departamento en el organigrama</h3>
{pasos([
 "Llama a <code>POST /api/v1/bk/organigrama</code> con <code>accion: unidad</code>.",
 "Indica el <b>DIP del titular</b> como <code>dip_actor</code>. Es la persona que tiene permiso para cambiar el organigrama.",
 "Si no indicas unidad superior, el departamento cuelga de la <b>Junta raíz</b> de la empresa.",
])}
<div class="ejemplo"><div class="et">Cuerpo de la petición</div><pre>{{ "accion": "unidad", "dip_actor": "23749931M", "tipo": "departamento", "nombre": "Comunicaciones" }}</pre>
<p class="res"><b>Resultado esperado:</b> el departamento aparece en el organigrama.</p></div>
{aviso("«Sin permiso para cambiar el organigrama»: el <code>dip_actor</code> no es el titular. No pongas la clave del banco ahí: el sistema pide una persona concreta.", "error")}

<h3>10.4 Ejemplo: convocar y conceder dentro de una empresa</h3>
{pasos([
 "Abre la convocatoria: <code>POST /api/v1/bk/empresas/&#123;id&#125;/convocatorias</code>. Un bono <b>exige</b> fecha de caducidad.",
 "Concede: <code>POST .../convocatorias/&#123;conv&#125;/concesiones</code> con beneficiario, importe y <code>dip_actor</code>. Se reserva el importe.",
 "Si la convocatoria ya no debe admitir más concesiones, ciérrala: <code>POST .../convocatorias/&#123;conv&#125;/cerrar</code>.",
])}
{tabla(["Si intentas…","El sistema responde…","Qué significa"], [
 ["Conceder a una cuenta de la propia empresa","«No se puede conceder a una cuenta de la propia empresa»","Bloqueo anti-autoconcesión. Elige otro beneficiario"],
 ["Conceder fuera del destino","«La convocatoria está dirigida a otra empresa»","Destino dirigido: solo puede recibir la empresa indicada"],
 ["Conceder con la convocatoria cerrada","«La convocatoria no está abierta hoy»","Fuera de fechas o cerrada"],
])}

<h3>10.5 Ejemplo: pagar la nómina de un mes</h3>
{pasos([
 "Asigna los complementos a los contratos (<code>.../complementos/asignaciones</code>). Si no indicas importe, se usa el importe base.",
 "Revisa los <b>conceptos del mes</b>: <code>GET .../nomina/conceptos?periodo=AAAA-MM</code>.",
 "Paga el periodo: <code>POST /api/v1/bk/nominas/periodos</code>. Paga salario y complementos.",
 "Pide los recibos: <code>GET .../nomina/recibos?periodo=AAAA-MM</code>, o con <code>dip=…&formato=pdf</code> para uno en PDF.",
])}
{aviso("El pago de nómina es <b>idempotente</b>: si repites la llamada, no paga dos veces. Aun así, no la repitas por impaciencia: revisa primero los recibos.", "consejo")}
{aviso("Quien asigna un complemento o autoriza un salario <b>no puede</b> ejecutar la nómina de ese periodo.", "consejo")}

<h3>10.6 Pasarela de pago</h3>
{pasos([
 "El comercio crea un <b>checkout</b> y recibe un código del tipo <code>PAG-XXXX-XXXX-XXXX-XXXX</code>.",
 "El usuario introduce el código en su banco.",
 "El banco pagador <b>canjea</b> el código y después <b>aprueba o rechaza</b> la operación.",
 "Si aprueba, se abona al comercio, descontando las comisiones.",
])}
""")

sec("11", "11. Empresas: tareas del titular", f"""
<p>El titular de una empresa trabaja por la API de banca, identificado con su DIP. Estas son las tareas habituales.</p>
{tabla(["Tarea","Qué hacer","Ruta"], [
 ["Ver el organigrama","Consultar unidades y nombramientos","Ficha de la empresa"],
 ["Añadir una cuenta","Vincular un IBAN de la entidad","<code>POST .../cuentas</code>"],
 ["Crear un departamento","Con <code>dip_actor</code> del titular","<code>POST /api/v1/bk/organigrama</code>"],
 ["Gestionar complementos","Catálogo y asignación a contratos","<code>.../complementos</code>"],
 ["Pagar la nómina","Revisar conceptos y pagar el periodo","<code>.../nomina/conceptos</code>, <code>/nominas/periodos</code>"],
 ["Abrir una convocatoria","Subvención o bono, dirigida o abierta","<code>.../convocatorias</code>"],
 ["Conceder","Reserva el importe al beneficiario","<code>.../concesiones</code>"],
 ["Cerrar una convocatoria","Deja de admitir concesiones nuevas","<code>.../cerrar</code>"],
])}
{ejemplo("Convocar un bono de 500 Pz para toda la entidad",
 "Una empresa quiere lanzar un bono cultural de 500 Pz, válido hasta el 30 de septiembre, abierto a cualquier beneficiario de la entidad.",
 ["Llama a <code>POST .../convocatorias</code> con: nombre «Bono cultura 2027», tipo <code>bono</code>, importe 500, desde 2027-01-01, hasta 2027-06-30, <b>caduca 2027-09-30</b>, destino <code>todos</code>, cuenta de fondos de la empresa, y tu <code>dip_actor</code>.",
  "Comprueba la respuesta: te devuelve el identificador de la convocatoria.",
  "Concede a un beneficiario con <code>.../concesiones</code>, por ejemplo 120 Pz."],
 "La convocatoria aparece en <b>Convocatorias de empresa</b> para la Junta. Los 120 Pz quedan reservados hasta que el beneficiario los canjee o caduquen.")}
{aviso("Si pones un bono sin caducidad, el sistema lo rechaza: «Un bono necesita fecha de caducidad». Es una protección, no un fallo.", "consejo")}
""")

sec("12", "12. Usuarios: tareas básicas", f"""
<p>El usuario trabaja desde la app o desde la API del usuario, con su propia sesión. Estas son las tareas más habituales, con ejemplos.</p>

<h3>12.1 Ver mi saldo y mis movimientos</h3>
{pasos(["Abre la app y entra en <b>Mi cuenta</b>.", "Mira el <b>saldo</b> de la cuenta principal y el de la tarjeta prepago (RBU).", "Pulsa un movimiento para ver su detalle, su referencia y su fecha."])}

<h3>12.2 Hacer una transferencia</h3>
{aviso("Los nombres de los botones de la app de usuario pueden variar según la versión. Si no encuentras uno, busca la acción equivalente y avísanos.", "consejo")}
{ventana("Cuenta", "Mi cuenta · Transferir", f'''
<b>Para</b> {selector("Cuenta de Luis · ES12…", 260)}<br><br>
<b>Importe (Pz)</b> {campo_lleno("25", 100)} &nbsp; <b>Concepto</b> {campo("Cena del viernes", 220)}<br><br>
{btn("Transferir","p")} &nbsp; {btn("Programar…","s")}''')}
{pasos([
 "Elige el <b>destinatario</b> (de tus beneficiarios guardados, o escribe su IBAN).",
 "Escribe el <b>importe</b> en Pz y, si quieres, un concepto.",
 "Pulsa <b>Transferir</b> para hacerla ahora, o <b>Programar…</b> para una fecha futura.",
])}
{ejemplo("Transferir 25 Pz y dejar otra programada",
 "Quieres pagar 25 Pz a Luis hoy, y dentro de un mes, otros 25 Pz.",
 ["Elige Luis, importe 25, concepto «Cena del viernes», pulsa <b>Transferir</b>.",
  "Pulsa <b>Programar…</b>, mismo destinatario e importe, y elige la fecha del próximo mes (formato AAAA-MM-DD).",
  "Confirma la programada."],
 "La transferencia inmediata sale ya. La programada aparece en tus movimientos programados y se ejecutará el día indicado.")}
{aviso("La fecha programada no puede estar en el <b>pasado</b> ni a más de <b>5 años</b>. Si el sistema lo rechaza, cambia la fecha; no es un fallo.", "error")}

<h3>12.3 Canjear un bono de la RBU</h3>
{ventana("RBU", "Mis bonos de la RBU", f'''
<table class="t"><tr><th>Semana</th><th>Importe</th><th>Caduca</th><th>Estado</th><th></th></tr>
<tr><td>2027-W02</td><td>5 Pz</td><td>2027-04-12</td><td>{chip("disponible")}</td><td>{btn("Canjear","p")}</td></tr>
<tr><td>2026-W46</td><td>5 Pz</td><td>2027-02-16</td><td>{chip("canjeado","#555")}</td><td></td></tr></table>''')}
{pasos([
 "Entra en <b>RBU</b> y mira la lista de bonos.",
 "Pulsa <b>Canjear</b> en el bono que quieras.",
 "El saldo entra en tu <b>cuenta principal</b>. <b>No caduca</b>: lo gastes o no.",
])}
{aviso("Un bono <b>sin canjear caduca a los 3 meses</b>. Si no lo canjeas, no sale ningún dinero de la Reserva. Canjéalo antes de la fecha de caducidad que aparece en la lista.", "consejo")}

<h3>12.4 Pagar una deuda o disputarla</h3>
{pasos([
 "En <b>Deudas</b>, mira el importe pendiente y la fecha de vencimiento.",
 "Pulsa <b>Pagar</b> e indica el importe. El sistema usa una clave de idempotencia: si se corta la conexión y repites, <b>no se paga dos veces</b>.",
 "Si crees que la deuda es incorrecta, pulsa <b>Disputar</b> dentro de los <b>60 días</b> desde el vencimiento. La disputa solo llega hasta lo que hayas pagado.",
])}
{ejemplo("Disputar una deuda que no reconoces",
 "Te reclaman 80 Pz de una cuota que ya pagaste en parte (50 Pz). Vencimiento: hace 20 días.",
 ["Entra en la deuda y pulsa <b>Disputar</b>.",
  "Escribe el motivo: <i>Cuota ya pagada parcialmente, justificante adjunto.</i>",
  "Confirma. La entidad o la Junta la resolverán en un plazo de 30 días."],
 "La disputa queda abierta. Mientras esté abierta, la deuda no se cobra automáticamente.")}

<h3>12.5 Mis datos y mi privacidad</h3>
{pasos(["Pide tu exportación desde la app. Recibirás todos tus datos: perfil, cuentas, movimientos, tarjetas (sin número completo), beneficiarios y sesiones (sin tokens). También está disponible por la API del usuario."])}
""")

sec("13", "13. Ejemplos de flujos completos", f"""
{ejemplo("Primer día de una entidad nueva",
 "Un banco nuevo se incorpora. Hay que dejarlo listo para operar.",
 ["La Junta da de alta la entidad y su clave de cliente.",
  "La entidad da de alta sus primeros clientes y cuentas personales.",
  "Dar de alta una empresa con su primera cuenta (crea su CIP y su organigrama).",
  "Probar en pruebas: una transferencia, un checkout y un pago de nómina con una persona de prueba.",
  "Revisar <b>Estado</b> hasta que no haya problemas críticos.",
  "Pasar a producción solo cuando las pruebas den lo esperado."],
 "La entidad opera con normalidad, con sus datos separados de las demás.")}

{ejemplo("Cambiar un límite de riesgo tras un incidente",
 "Se detecta un patrón de transferencias sospechoso. La Junta decide bajar el límite diario de una entidad.",
 ["Propone el cambio en <b>Configuración</b>, con el ámbito de la entidad (si el ajuste lo permite) o global.",
  "Escribe el motivo con la referencia del incidente.",
  "Otra persona de la Junta lo aprueba.",
  "Registra en la incidencia el cambio y su hora."],
 "El límite cambia y queda la traza completa en Registros, lista para la revisión del incidente.")}

{ejemplo("Subvención con reversión sin saldo suficiente",
 "Una subvención pagó 120 Pz. El beneficiario solo tiene 30 Pz disponibles y se detecta una infracción.",
 ["Revertir… con motivo de al menos 10 caracteres.",
  "El sistema devuelve 30 Pz de inmediato.",
  "Los 90 Pz restantes quedan como deuda del beneficiario.",
  "Generar el informe PDF para el expediente."],
 "Se recuperan 30 Pz de inmediato, y 90 Pz se cobrarán cuando el beneficiario tenga fondos. No queda saldo negativo.")}
""")

sec("14", "14. Gestión de incidencias", f"""
<p>Una incidencia es cualquier cosa que no funciona como debería: un botón que falla, un dato que no cuadra, un pago que no llega, un acceso que no reconoces. Esta sección dice qué hacer, en qué orden y a quién avisar.</p>

<h3>14.1 Tipos de incidencia</h3>
{tabla(["Tipo","Ejemplos","Quién la detecta"], [
 ["<b>Dinero</b>","Un pago que no llega, un abono duplicado, un saldo que no cuadra","Cualquiera que lo vea"],
 ["<b>Seguridad</b>","Un acceso que no reconoces, una clave que pudo filtrarse, un correo sospechoso","Cualquiera: no esperes"],
 ["<b>Funcionamiento</b>","Un botón que falla, una pantalla que no carga, un error «No se ha podido cargar»","Quien usa el panel"],
 ["<b>Datos</b>","Una fecha absurda, un importe mal formateado, un registro duplicado","Quien revisa"],
 ["<b>Consulta</b>","Cómo se hace algo, por qué aparece un mensaje","Cualquiera"],
])}

<h3>14.2 Gravedad y respuesta</h3>
<p>La gravedad la decide quien la detecta, y se puede subir si luego resulta peor. Los tiempos son una <b>propuesta</b> que la Junta debe validar:</p>
{tabla(["Gravedad","Cuándo","Respuesta propuesta"], [
 ["<b>Crítica</b>","Dinero mal movido, posible acceso indebido, sistema caído para todos","Avisar de inmediato. Atender en menos de 1 hora"],
 ["<b>Alta</b>","Un flujo importante está bloqueado (por ejemplo, no se puede pagar la nómina)","Atender el mismo día"],
 ["<b>Media</b>","Una función falla pero hay alternativa","Atender en 2 días laborables"],
 ["<b>Baja</b>","Cosmético, consulta o mejora","Revisar en la siguiente reunión"],
])}

<h3>14.3 Los primeros cinco minutos</h3>
<ul class="check-lista">
<li>Para. <b>No repitas</b> ninguna operación de dinero (pago, concesión, reversión) hasta saber si ya se hizo.</li>
<li>Haz una <b>captura de pantalla</b> o copia el texto exacto del mensaje.</li>
<li>Anota la <b>hora</b> (con zona), la <b>pantalla</b>, el <b>DIP</b> o la cuenta afectada y, si lo sabes, el identificador del elemento.</li>
<li>Mira en <b>Registros</b> si la acción se hizo, y quién la hizo.</li>
<li>Mira en <b>Estado</b> si hay problemas críticos.</li>
<li>Avisa según la gravedad (sección 14.5). Si es crítica, no esperes a tener todos los datos.</li>
</ul>
{aviso("Si la incidencia es de <b>seguridad</b> (acceso que no reconoces), además de avisar: cambia tu contraseña y pide a la Junta que revise las sesiones abiertas. No borres ningún registro.", "peligro")}

<h3>14.4 Cómo reportar una incidencia</h3>
<p>Usa esta plantilla. Cuanto más completa, más rápido se resuelve.</p>
{tabla(["Campo","Qué poner","Ejemplo"], [
 ["Título","Una frase clara","Error al pagar la nómina de noviembre"],
 ["Gravedad","Crítica, Alta, Media o Baja","Alta"],
 ["Quién y dónde","Tu nombre, tu rol y la pantalla o la ruta","Ana Ruiz (Junta), Financiación → Justificaciones"],
 ["Qué esperabas","Lo que debía pasar","Que se pagara la justificación de 120 Pz"],
 ["Qué pasó","Lo que pasó, con el mensaje exacto","«No se ha podido cargar. Previsiones: …»"],
 ["Cuándo","Fecha y hora con zona","2026-11-21 16:02 (Madrid)"],
 ["Elementos afectados","Identificadores, DIP, IBAN (si ayuda)","Concesión 9b8a7f6e…"],
 ["Pasos para repetirlo","Lo mínimo para reproducirlo","1. Abrir… 2. Pulsar… 3. Ver error"],
 ["Lo que ya has hecho","Para no repetir lo que no sirvió","Reintentar: mismo error"],
 ["Capturas o adjuntos","Pantalla y, si existe, el registro de Registros","captura_error.png"],
])}

<h3>14.5 A quién avisar</h3>
<p>El canal oficial para incidencias debe definirlo la Junta. Mientras tanto, estos son los contactos ya registrados en el proyecto:</p>
{tabla(["Para qué","Contacto","Cuándo"], [
 ["Responsable técnico","Mikel Alegre (DIP-23749931M)","Incidencias de funcionamiento, datos y dinero"],
 ["Seguridad","malegre@laplaceta.org","Cualquier sospecha de acceso indebido o de filtración"],
 ["Canal oficial de incidencias","PENDIENTE: definir por la Junta","—"],
])}
{aviso("Los contactos de la tabla son los que consta en el proyecto. Si alguno ha cambiado, la Junta debe actualizar esta guía.", "consejo")}

<h3>14.6 Incidencias con dinero: reglas que no se negocian</h3>
<ul>
<li><b>Idempotencia:</b> los pagos y las concesiones llevan clave de idempotencia. Repetir la misma petición no duplica el movimiento. Aun así, no la repitas sin mirar Registros.</li>
<li><b>Reversiones:</b> una reversión necesita motivo y deja traza. Nunca deja saldo negativo: lo que no se puede devolver queda como deuda.</li>
<li><b>Correcciones:</b> un error de dinero se corrige con un movimiento contrario y se documenta. <b>Nunca</b> se edita un movimiento ya hecho.</li>
</ul>

<h3>14.7 Cerrar una incidencia y aprender de ella</h3>
{pasos([
 "Confirma que el problema <b>ya no ocurre</b> (prueba la misma acción de nuevo, en pruebas si es posible).",
 "Anota la <b>causa</b> y la <b>solución</b> en la incidencia.",
 "Si afecta a dinero o a seguridad, haz un breve <b>informe posterior</b>: qué pasó, por qué, qué se ha cambiado y qué se hará para que no vuelva a pasar.",
 "Si la solución cambia algún proceso, actualiza esta guía.",
])}
""")

sec("15", "15. Tabla de errores ampliada", f"""
<p>Los mensajes que más te vas a encontrar, con lo que significan y lo que debes hacer.</p>
{tabla(["Mensaje","Qué significa","Qué hacer"], [
 ["«El proponente no puede aprobar su propio cambio»","Intentas aprobar algo que tú mismo propusiste","Pide a otra persona que lo apruebe"],
 ["«Publicar exige un aprobador distinto del autor»","Quien redactó la versión fiscal intenta publicarla","Que la publique otra persona de Fiscal"],
 ["«Este ajuste solo se cambia en el ámbito global»","Estás en una entidad y el ajuste es global","Cambia el ámbito a Global"],
 ["«Sin permiso para cambiar el organigrama»","El <code>dip_actor</code> no es el titular","Usa el DIP del titular de la empresa"],
 ["«Una unidad de tipo … necesita una unidad padre»","El tipo de unidad necesita un padre concreto","Indica la unidad superior, o deja el campo vacío"],
 ["«Supera el presupuesto…»","La concesión rebasa lo disponible","Reduce el importe o revisa el presupuesto"],
 ["Mensajes de saldo insuficiente (el texto varía según la operación)","No hay saldo en la cuenta que paga","Reduce el importe o espera a que haya fondos"],
 ["«Un bono necesita fecha de caducidad»","Falta la caducidad en un bono","Pon la fecha o usa una convocatoria con caducidad"],
 ["«No se puede conceder a una cuenta de la propia empresa»","Bloqueo anti-autoconcesión","Elige otro beneficiario"],
 ["«La convocatoria está dirigida a otra empresa»","Destino dirigido a una empresa concreta","Concede solo a esa empresa"],
 ["«La convocatoria no está abierta hoy»","Fuera de sus fechas o cerrada","Revisa las fechas, o abre otra convocatoria"],
 ["«La subvención no está activa»","Caducada o revertida","Consulta su estado en Concesiones"],
 ["«Ya pagada o rechazada»","La justificación ya se resolvió","No hace falta hacer nada"],
 ["«Transacción no elegible o importe excesivo»","El gasto no cumple los requisitos","Revisa la transacción y el importe"],
 ["«Supera lo concedido»","Las justificaciones superan la concesión","Revisa las justificaciones pendientes"],
 ["«Solo el subvencionante o la Junta pueden revertir abonos»","Tu rol no permite revertir","Pide la reversión a la entidad que concedió"],
 ["«El motivo debe tener al menos N caracteres»","El motivo es demasiado corto","Escribe una explicación completa"],
 ["«fecha en el pasado»","La fecha programada ya pasó","Pon una fecha futura"],
 ["«fecha demasiado lejana (máximo 5 años)»","Fecha programada a más de 5 años","Acorta la fecha"],
 ["«fecha debe ser ISO 8601»","Formato de fecha incorrecto","Usa AAAA-MM-DD"],
 ["«date/time field value out of range»","Una fecha con formato incorrecto llegó a la base de datos","Avisa: es un error de la pantalla (incidencia de datos)"],
 ["«No se ha podido cargar»","Fallo al leer los datos","Pulsa Reintentar; si persiste, avisa con el texto"],
 ["Acceso denegado (403) o «No autorizado»","Tu rol no tiene acceso a esa pantalla","Pide acceso a la Junta"],
 ["«Denegado» (API)","La clave o la firma no son válidas","Revisa la clave y la firma; no la compartas"],
])}
{aviso("Si un mensaje no está en esta tabla, <b>no lo ignores</b>: cópialo tal cual y avísanos. Lo añadimos.", "consejo")}
""")

sec("16", "16. Preguntas frecuentes", f"""
{tabla(["Pregunta","Respuesta corta"], [
 ["¿Por qué no aparece un botón?","Porque la acción no está permitida en el estado actual de ese elemento (por ejemplo, «Cerrar» solo aparece en convocatorias abiertas)."],
 ["¿Puedo cambiar un ajuste yo solo?","No. Siempre lo propones y lo aprueba otra persona."],
 ["¿Por qué la Junta no puede aprobar sus propios cambios?","Porque la doble firma no tiene excepciones: protege a la Junta también."],
 ["¿Qué pasa si revierto un abono y el beneficiario no tiene saldo?","Lo disponible vuelve y el resto queda como deuda. Nunca queda saldo negativo."],
 ["¿Un bono canjeado puede caducar?","No. Lo canjeado va a la cuenta principal y no caduca."],
 ["¿Un bono sin canjear?","Caduca a los 3 meses. Si caduca, no sale dinero de la Reserva."],
 ["¿Puedo hacer una transferencia programada para ayer?","No. La fecha no puede estar en el pasado."],
 ["¿Por qué mi pago de nómina no se repite?","Porque el pago es idempotente: ya se pagó ese periodo a esa persona."],
 ["¿Puedo ver los datos de otra entidad?","No. Cada entidad solo ve los suyos."],
 ["¿Cómo sé quién cambió algo?","En Registros: autor, fecha, hora y motivo."],
 ["¿Qué es la reserva?","Dinero bloqueado para una subvención o convocatoria hasta que se paga o caduca."],
 ["¿Puedo cerrar una convocatoria y volver a abrirla?","Cerrarla es definitivo: para más concesiones, abre otra convocatoria."],
 ["¿Los recibos de nómina tienen formato legal?","No todavía: son recibos de texto simple."],
 ["¿Dónde está la lista completa de rutas de la API?","En docs/openapi.json."],
 ["¿Qué hago si la pantalla no carga?","Pulsa Reintentar. Si persiste, mira Estado y avisa con el mensaje exacto."],
 ["¿Cómo doy de baja a alguien del panel?","Pide a la Junta que lo haga, con otra persona que lo revise."],
])}
""")

sec("17", "17. Anexo: listas de comprobación", f"""
<h3>Cada día (Junta)</h3>
<ul class="check-lista">
<li>Revisar <b>Estado</b>: ningún problema crítico sin atender.</li>
<li>Revisar <b>Pendientes de aprobación</b> en Configuración.</li>
<li>Revisar <b>Justificaciones</b> pendientes de pagar.</li>
<li>Revisar las <b>convocatorias abiertas</b> con caducidad próxima.</li>
<li>Revisar <b>Registros</b> de las últimas 24 horas: nada inesperado.</li>
</ul>
<h3>Cada semana (Junta)</h3>
<ul class="check-lista">
<li>Revisar las <b>disputas</b> abiertas y sus plazos.</li>
<li>Revisar los <b>productos</b> en borrador.</li>
<li>Revisar los <b>informes PDF</b> de las subvenciones activas.</li>
</ul>
<h3>Antes de un cambio importante</h3>
<ul class="check-lista">
<li>Probado en <b>pruebas</b>, con el resultado esperado.</li>
<li>Motivo escrito y norma que lo justifica.</li>
<li>Otra persona lista para aprobar.</li>
<li>Persona de contacto avisada si afecta a clientes.</li>
</ul>
<h3>Al terminar una sesión</h3>
<ul class="check-lista">
<li>Pulsado <b>Salir</b>.</li>
<li>Cerrado el navegador si el equipo es compartido.</li>
</ul>
""")

sec("18", "18. Límites conocidos", f"""
{aviso("Esta guía describe el código tal como está. Antes de confiar en ella al cien por cien, hay que comprobar en el entorno real.", "aviso")}
<ul>
<li>Las pantallas <b>no se han probado en un navegador real</b>. La verificación confirma que el código compila, no el aspecto ni el orden exacto de los botones.</li>
<li>Las <b>deudas cobradas tras una reversión</b> se recuperan, pero no se vuelven a autorizar salvo que la convocatoria lo permita.</li>
<li>Las <b>empresas no tienen pantalla propia</b>: operan por la API de banca.</li>
<li>Los <b>recibos de nómina</b> son de texto simple, sin logotipo ni formato legal.</li>
<li>La <b>subida de logotipos</b> valida la estructura del archivo, pero no lo re-codifica ni lo analiza con antivirus.</li>
<li>El <b>canal oficial de incidencias</b> está pendiente de definir por la Junta.</li>
<li>Nada de esto se ha ejecutado todavía en la base de datos de producción.</li>
</ul>
""")

# ============================ ENSAMBLADO ============================
portada = """
<section class="portada">
  <h1>Placeta One</h1>
  <div class="sub">Guía de uso paso a paso</div>
  <p style="margin-top:24px">Para la Junta, las entidades, las empresas y los usuarios.</p>
  <p>Versión de la guía: <b>1.0 (borrador para revisión)</b></p>
  <p>Fecha: 21 de noviembre de 2026</p>
  <p>Responsable técnico: <b>Mikel Alegre</b> (DIP-23749931M) · Seguridad: malegre@laplaceta.org</p>
  <div class="pie">
    Estado: las pantallas aún no se han probado en un navegador real. Los dibujos son esquemas para orientarte.<br>
    Documento interno del Grupo de La Placeta. Money en Placetas (Pz).
  </div>
</section>"""

indice = '<section class="indice"><h2>Índice</h2><ol>' + "".join(
    f'<li><a href="#s{i}">{E(t)}</a></li>' for i, t, _ in SEC) + '</ol></section>'

cuerpo = "".join(f'<section id="s{i}">' + f'<h2>{E(t)}</h2>' + c + '</section>' for i, t, c in SEC)
# Las secciones ya traen su propio título dentro de su cuerpo cuando hace falta; aquí usamos el título como cabecera.

doc = f"""<!doctype html><html lang="es"><head><meta charset="utf-8">
<title>Placeta One · Guía de uso</title><style>{CSS}</style></head>
<body>{portada}{indice}{cuerpo}</body></html>"""

out = pathlib.Path("/home/claude/guia/guia.html")
out.write_text(doc, encoding="utf-8")
print("HTML generado:", out, "| secciones:", len(SEC), "| tamaño KB:", round(len(doc.encode()) / 1024))
