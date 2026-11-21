# Guía de uso de Placeta One

Esta guía explica, paso a paso, cómo hacer las tareas más habituales en Placeta One, según quién eres. Para las rutas exactas de la API, sus parámetros y ejemplos, consulta `docs/openapi.json`. Para los flujos en diagrama, consulta `docs/FLUJOS.md`.

> **Aviso.** Esta guía describe el comportamiento del código. Las pantallas del panel **todavía no se han probado en un navegador** en un entorno real. Si un botón o un texto no coincide con lo que ves, avisa: lo corregimos. Y antes de usar nada con dinero real, prueba la tarea en la base de pruebas.

---

## 0. Antes de empezar

### Qué es Placeta One
Es el sistema bancario interno del Grupo de La Placeta. Todo el dinero se mide en **Placetas (Pz)**. Maneja cuentas, pagos, la RBU (renta básica), subvenciones y bonos, empresas con su organigrama y su nómina, y las finanzas institucionales.

### Quién hace qué

| Rol | Qué puede hacer | Dónde |
|---|---|---|
| **Junta (administrador)** | Todo lo de sistema: ajustes, impuestos, productos, bancos, subvenciones, convocatorias de empresa | Panel de administración |
| **Personal** | Acceso al panel según su rol (en la práctica, hoy solo la Junta entra) | Panel |
| **Entidad (banco)** | Sus clientes, cuentas, empresas, pasarela y programas, **solo de su entidad** | API de banca |
| **Titular de una empresa** | Organigrama, cuentas, complementos, nómina y convocatorias de su empresa | API de banca, con su DIP |
| **Usuario** | Su cuenta, transferencias, bonos RBU, deudas y sus datos | App y API del usuario |

### Dos entornos
- **Pruebas**: para ensayar. Aquí se puede romper todo sin consecuencias.
- **Producción**: dinero real.

**Regla de oro:** cualquier tarea nueva, primero en pruebas.

### Conceptos que aparecen en toda la guía
- **DIP**: identificador de una persona (por ejemplo `DIP-23749931M`). Las acciones de empresa se firman con el DIP del titular.
- **CIP**: identificador de una entidad institucional (por ejemplo `CIP-00000004`). Cada empresa tiene el suyo, y se crea solo al añadirle su primera cuenta.
- **Doble firma**: algunas acciones necesitan que **otra persona** la apruebe. Nadie aprueba su propio cambio, ni siquiera la Junta.
- **Reserva**: dinero bloqueado para una subvención o convocatoria. No se puede gastar hasta que se paga o caduca.

---

## 1. Entrar en el panel de administración (Junta)

1. Abre la web del panel y entra con tu **email y contraseña de personal**.
2. El menú lateral agrupa las secciones: Panel, Estado, Bancos, Clientes, Cuentas, Productos, Operaciones, Financiación, Normas, Disputas, Fiscalidad, Registros, Personal, API, Numeración, Procesos, Configuración, Consola… y, según la versión, Empresas, Organigrama, Institucional, Pasarela, Liquidación, Tasas, Comercios, IVA, Previsiones, Destinos y Convocatorias de empresa.
3. Las pantallas muestran **tablas con filas**. Cada fila tiene botones de acción a la derecha. Si un botón no aparece, es que la acción no está permitida en el estado actual de ese elemento.

**Si ves un error con el texto «No se ha podido cargar»:** pulsa **Reintentar**. Si vuelve a salir, copia el texto del error y avísanos.

---

## 2. Ajustes del sistema (Configuración)

Los ajustes controlan límites, plazos y topes (por ejemplo, el importe semanal de la RBU o la caducidad de los bonos). **Ningún ajuste se cambia directamente**: se propone y lo aprueba otra persona.

### Cómo cambiar un ajuste
1. Entra en **Configuración → Ajustes**.
2. Busca el ajuste (caja de búsqueda) o filtra por categoría (Aprobaciones, RBU y bienestar, Cobros, Cuentas, Finanzas, Fiscalidad…).
3. Cambia el valor con su control: un interruptor para sí/no, un selector si hay opciones cerradas, o un número con su rango visible.
4. Aparece **«Motivo (obligatorio)»**. Escribe por qué cambias el valor (mínimo 5 caracteres).
5. Pulsa **Proponer cambio**. El ajuste queda **pendiente**.
6. **Otra persona** entra en el bloque **«Pendientes de aprobación»** y pulsa **Aprobar** o **Rechazar**.

### Ámbito global o por entidad
- Arriba, en **Ámbito**, eliges **Global** o una entidad concreta.
- Algunos ajustes solo se cambian en **Global**. Si eliges una entidad, aparecen deshabilitados con la nota «Solo se cambia en el ámbito global».
- Los ajustes marcados con **🔒 2ª persona** siempre necesitan aprobación de otra persona.

### Errores típicos
- «El proponente no puede aprobar su propio cambio»: pide a otra persona que lo apruebe.
- «Este ajuste solo se cambia en el ámbito global»: pon el ámbito en Global.

---

## 3. Crear un impuesto nuevo (Configuración → Nuevo impuesto)

Es un asistente de **cuatro pasos**. Puedes volver atrás en cualquier momento.

**Paso 1. Impuesto**
- Si el impuesto ya tiene norma, elígela en **Norma existente**. Si no, deja «nueva norma» y rellena **código** (2 a 10 letras mayúsculas, números o guion bajo), **nombre**, **límite central (%)** y **cuenta recaudadora**.

**Paso 2. Cómo se cobra**
- Elige **Porcentaje** (un % de cada operación) o **Importe fijo** (una cantidad en Pz por operación).
- Rellena el valor. Mínimo y máximo son opcionales.
- Aparece una **vista previa** en lenguaje claro y un ejemplo con 100 Pz. Revísala: es lo que se cobrará.

**Paso 3. Vigencia y alcance**
- **Entra en vigor**: fecha de inicio. **Fin**: opcional.
- **Entidad**: todas, o una concreta.
- **Operaciones anteriores**: elige entre *No aplicar* (solo afecta desde la entrada en vigor), *Solo simular* (calcula el efecto sobre el pasado sin cobrar) o *Aplicar automáticamente* (cobra también sobre el pasado). Usa *No aplicar* salvo que la Junta haya decidido otra cosa.
- **Motivo y norma que lo justifica** (obligatorio, mínimo 10 caracteres).

**Paso 4. Revisar y crear**
- Pulsa **Crear como borrador**. Queda como borrador: todavía no está en vigor.
- Para publicarla, **otra persona de Fiscal** pulsa **Publicar**. Quien redactó la versión no puede publicarla.

---

## 4. Productos

Un producto es lo que se contrata (una cuenta, una tarjeta…). Cada producto tiene un **estado**: borrador, activo o retirado.

### Crear un producto
1. Entra en **Productos → Nuevo** (o el botón de alta).
2. Rellena código, nombre, tipo, límites y fechas.
3. Marca **Aprobación automática** si quieres que se active al guardarlo, sin revisión manual. Si no la marcas, queda en **borrador**.

### Activar un producto
- **Aprobar y activar**: pasa un borrador a activo. Queda registrado quién lo aprobó.
- **Activar aprobación automática / Quitar aprobación automática**: cambia la marca en un producto ya existente. Activarla sobre un borrador lo activa de inmediato.
- **Retirar**: deja de ofrecerse. **Descartar**: borra un borrador que no se va a usar.

---

## 5. Subvenciones y bonos (Financiación)

Esta es la pantalla más importante para el dinero público. El flujo tiene **cinco pasos**, y la pantalla los muestra arriba:

1. **Programa**: el marco de la ayuda, con su presupuesto y su cuenta de fondos.
2. **Concesión**: reserva el importe. Si no hay fondos o se supera el presupuesto, **no se crea**.
3. **Justificación**: el beneficiario presenta un gasto de su cuenta. Se comprueba que sea elegible y que no supere lo concedido.
4. **Abono**: se paga lo justificado. Es el único paso que mueve dinero hacia el beneficiario.
5. **Caducidad o reversión**: lo no usado caduca y se libera. Un abono se puede revertir.

### 5.1 Conceder una subvención o un bono
1. En **Financiación → Concesiones**, pulsa **+ Nueva concesión**.
2. Elige el **programa**, el **beneficiario** (cuenta) y el **importe** en Pz.
3. Opcional: elige una **convocatoria**. Si la elegiste, hereda su caducidad.
4. **Caduca**: obligatoria en los **bonos**. Debe ser posterior a hoy.
5. Pulsa **Conceder y reservar**.

Si sale un error de fondos o de presupuesto, no se ha concedido nada: revisa el importe o el saldo del programa.

### 5.2 Justificar y pagar un gasto
1. En **Justificaciones y abonos**, pulsa crear.
2. Elige la **concesión**, la **transacción** del beneficiario que justifica el gasto, el **nº de factura** y el **importe**.
3. La justificación queda pendiente. Pulsa **Aprobar y pagar** para abonar. El abono consume la reserva.
4. Si no procede, pulsa **Rechazar**.

### 5.3 Revertir un abono
Úsalo si se detecta una infracción o un incumplimiento de requisitos.

1. En la tabla de **Concesiones**, pulsa **Revertir…**.
2. Escribe el **motivo** (mínimo 10 caracteres). Ese motivo queda en la auditoría.
3. Qué pasa después depende del saldo del beneficiario:
   - **Si tiene saldo:** el abono se revierte entero y el dinero vuelve al programa.
   - **Si no tiene saldo suficiente:** lo disponible vuelve de inmediato, y lo que falta queda como **deuda** del beneficiario. El sistema lo cobra cuando tenga fondos. **Nunca queda saldo negativo.**
4. La justificación queda **rechazada**, así que no se puede pagar dos veces.

### 5.4 Informe de justificación
- En la fila de la concesión, pulsa **Informe PDF**. Sale un resumen: concedido, aprobado, pagado, pendiente, justificaciones, abonos revertidos y deuda.

### 5.5 Caducidad y reautorización por convocatoria
En **Convocatorias** (dentro de Financiación o en **Convocatorias de empresa**):
- **Caducidad de bonos**: fecha. Pulsa **Guardar**. Aplica a los bonos **nuevos** de esa convocatoria.
- **Reautorizar lo recuperado**: marca la casilla si quieres que lo que se cobre de una deuda por reversión vuelva a quedar reservado para esa convocatoria. Solo se reautoriza si la subvención sigue activa, no ha caducado y la convocatoria está **abierta**.

---

## 6. Convocatorias de empresa (Convocatorias de empresa)

Las empresas pueden **convocar** subvenciones y bonos, abiertos a toda la entidad o dirigidos a una empresa concreta. Como Junta, aquí las **supervisas**.

Para cada convocatoria ves: la **empresa** que convoca, su **destino** (toda la entidad o una empresa), la **cuenta de fondos**, la vigencia, lo concedido frente al importe y lo pagado.

- **Cerrar**: pide confirmación. Desde ese momento no admite concesiones nuevas. Lo ya concedido sigue su curso.
- **Concesiones (n)**: despliega la lista de beneficiarios, con su importe, lo pagado, el estado y la caducidad.
- **Caducidad** y **reautorizar** igual que en el apartado 5.5.

Para **abrir** una convocatoria, la empresa lo hace por la API de banca con su titular (ver sección 9.3).

---

## 7. Impuestos, normas y topes

- **Fiscalidad**: impuestos y versiones publicadas. Las versiones se redactan como borrador y las publica otra persona.
- **Normas**: normas y topes. Los cambios de topes son ajustes y siguen la doble firma.
- **Disputas**: una deuda puede disputarse dentro de su plazo. Una disputa de más de **1.000 Pz** necesita dos personas distintas para resolverla.

---

## 8. Estado del sistema y registros

- **Estado**: comprobaciones de salud del sistema. Si aparece un **problema crítico**, es lo primero que hay que mirar.
- **Registros**: auditoría. Cada acción importante queda con su autor, su fecha y su motivo. Úsala para cualquier investigación.
- **Consola**: herramienta técnica. Úsala solo si sabes lo que haces y, mejor, en pruebas.

---

## 9. Trabajar por la API de banca (entidades y empresas)

La API de banca es para las **entidades**. Cada entidad solo ve y opera **sus** clientes, cuentas y empresas. Todas las llamadas van firmadas y con la clave de la entidad. Las rutas, sus parámetros y ejemplos están en `docs/openapi.json`.

### 9.1 Clientes y cuentas
- Dar de alta clientes y consultar sus cuentas y movimientos.
- Abrir sesión de usuario para una persona concreta (`POST /api/v1/sessions`), con permisos concretos.

### 9.2 Pasarela de pago (cobros)
1. El comercio crea un **checkout** (`POST /api/v1/bk/checkouts`) y recibe un código **PAG-XXXX-XXXX-XXXX-XXXX**.
2. El usuario introduce el código en su banco.
3. El banco pagador lo **canjea** (`POST /api/v1/bk/pagos/canjear`) y después **aprueba o rechaza** la operación (`POST /api/v1/bk/pagos/{id}/resolucion`).
4. Si aprueba, se abona al comercio, descontando las comisiones configuradas.

### 9.3 Empresas: alta, cuentas y organigrama
1. **Dar de alta la empresa** y su **primera cuenta de empresa**. En ese momento se crea su **entidad institucional** con su CIP, y el organigrama inicial (una Junta raíz, un puesto de titular con todos los permisos y el titular nombrado).
2. **Añadir más cuentas**: `POST /api/v1/bk/empresas/{id}/cuentas` con el IBAN. Los titulares reciben acceso a la cuenta según su rol.
3. **Crear unidades del organigrama**: `POST /api/v1/bk/organigrama` con `accion: unidad`. Un departamento cuelga de la Junta raíz si no indicas padre.
   - El `dip_actor` debe ser el **DIP del titular**. Sin él, la API responde «Sin permiso para cambiar el organigrama».

### 9.4 Complementos de actividad y nómina (NEXE)
1. **Catálogo**: `POST /api/v1/bk/empresas/{id}/complementos` crea un complemento (código, nombre, fijo o variable, importe base).
2. **Asignar a un contrato** (la retribución de una persona): `POST .../complementos/asignaciones`. Si no pones importe, se usa el importe base.
3. **Retirar** una asignación a partir de una fecha: `POST .../asignaciones/{asig}/retirar`.
4. **Conceptos del mes** (lo que va a cobrar cada persona): `GET .../nomina/conceptos?periodo=AAAA-MM`.
5. **Pagar la nómina del periodo**: `POST /api/v1/bk/nominas/periodos`. Paga salario y complementos vigentes. Es **idempotente**: repetir la llamada no paga dos veces.
6. **Recibos**: `GET .../nomina/recibos?periodo=AAAA-MM` (JSON) o con `dip=DIP&formato=pdf` (un recibo en PDF por persona).

> Quien asigna un complemento o autoriza un salario **no puede** ejecutar la nómina de ese periodo.

### 9.5 Convocatorias de una empresa
1. **Abrir**: `POST /api/v1/bk/empresas/{id}/convocatorias` con nombre, tipo (subvención o bono), importe, fechas, destino (`todos` o `empresa`), cuenta de fondos (de la empresa) y el `dip_actor` del titular.
   - Un **bono** exige fecha de caducidad.
2. **Conceder**: `POST .../convocatorias/{conv}/concesiones` con beneficiario, importe y, opcionalmente, caducidad.
   - No se puede conceder a una cuenta de la propia empresa.
   - Si la convocatoria está dirigida a una empresa, solo se puede conceder a ella.
3. **Cerrar**: `POST .../convocatorias/{conv}/cerrar`.
4. **Reautorización**: `POST /api/v1/bk/convocatorias/{id}/reautorizacion`.

### 9.6 Subvenciones desde la API de banca
- **Crear** una subvención o bono de un programa de la entidad: `POST /api/v1/bk/subvenciones`.
- **Revertir** un abono o la subvención completa: `POST /api/v1/bk/subvenciones/{id}/revertir`, con motivo de al menos 10 caracteres. Requiere permiso de ejecutar en la entidad.
- **Informe**: `GET /api/v1/bk/subvenciones/{id}/informe` (JSON, o `formato=pdf`).

### 9.7 Webhooks, claves y sesiones
- Los **webhooks** avisan a la entidad de eventos (por ejemplo, un pago aprobado). Tienen su propia clave, que se puede rotar.
- Las **claves de cliente** se pueden rotar o desactivar.

---

## 10. Como usuario (app y API del usuario)

### 10.1 Ver tu saldo y tus movimientos
- Tu cuenta principal, sus movimientos y tu saldo de tarjeta prepago (`GET /api/v1/me/accounts`, `GET /api/v1/me/rbu/saldo`).

### 10.2 Hacer una transferencia
- **Inmediata**: `POST /api/v1/me/transfers`.
- **Programada**: `POST /api/v1/me/transfers/scheduled` con fecha **ISO** (`AAAA-MM-DD` o `AAAA-MM-DDTHH:MM`).
  - No puede estar **en el pasado** (más de un día) ni a **más de 5 años**.
- Puedes guardar **beneficiarios** para no volver a escribir sus datos.

### 10.3 Canjear un bono de la RBU
1. Consulta tus bonos: `GET /api/v1/me/rbu`.
2. Canjea el que quieras: `POST /api/v1/me/rbu/{id}/claim`.
3. El saldo entra en tu **cuenta principal** y **no caduca**, lo gastes o no.

**Importante:** un bono **sin canjear caduca a los 3 meses**. Si nadie lo canjea, no sale ni un céntimo de la Reserva.

### 10.4 Pagar una deuda o disputarla
- **Pagar**: `POST /api/v1/me/deudas/{id}/pagar`. Envía siempre una **clave de idempotencia**: si repites la misma petición, no se paga dos veces.
- **Disputar**: se puede hacer dentro de **60 días** desde el vencimiento y solo hasta lo que hayas pagado. La entidad acreedora o la Junta la resuelven en un plazo de 30 días.

### 10.5 Previsiones y avisos
- `GET /api/v1/me/previsiones?desde=AAAA-MM-DD&hasta=AAAA-MM-DD`: lo que se va a cobrar o pagar en esas fechas (impuestos, cuotas, nóminas, programadas, deudas, RBU). Máximo 366 días.

### 10.6 Tus datos (RGPD)
- `GET /api/v1/me/exportar`: descarga todos tus datos (perfil, cuentas, movimientos, tarjetas sin número completo, beneficiarios y sesiones sin tokens).

---

## 11. Ejemplos de flujo completo

### Ejemplo A. Una empresa convoca un bono y un vecino lo canjea
1. La entidad da de alta la empresa y su primera cuenta de empresa. Se crea su CIP.
2. El titular **abre la convocatoria** de bono: destino «toda la entidad», caducidad 30 de septiembre, cuenta de fondos de la empresa.
3. El titular **concede** 120 Pz a la cuenta de un usuario. Se reservan 120 Pz.
4. El usuario ve el bono en su app y **lo canjea** antes de la caducidad. Los 120 Pz pasan a su cuenta principal y ya no caducan.
5. La Junta, en **Convocatorias de empresa**, ve la convocatoria con 120 Pz concedidos y pagados.

### Ejemplo B. Una subvención con infracción y reversión
1. La Junta **concede** 500 Pz de un programa a una entidad. Se reservan.
2. El beneficiario **justifica** 120 Pz de un gasto elegible. La Junta **aprueba y paga**. Se consumen 120 Pz de la reserva.
3. Se detecta una infracción. En **Concesiones → Revertir…**, la Junta escribe el motivo.
4. Si el beneficiario tiene saldo, los 120 Pz vuelven al programa. Si no, lo disponible vuelve y el resto queda como **deuda** que se cobrará cuando tenga fondos.
5. Se genera el **Informe PDF** para el expediente.

### Ejemplo C. Pagar la nómina de un mes
1. El titular **asigna** el complemento «Actividad de campo» a un contrato, con 150 Pz.
2. Antes de pagar, revisa **conceptos del mes**: salario y complemento de cada persona.
3. Ejecuta **pagar el periodo**. Se paga salario y complementos, con una transferencia por línea.
4. Pide los **recibos** en PDF si hace falta.
5. Si repite la llamada, **no se vuelve a pagar**.

---

## 12. Errores frecuentes y qué significan

| Mensaje | Qué significa | Qué hacer |
|---|---|---|
| «El proponente no puede aprobar su propio cambio» | Quien propuso el cambio intenta aprobarlo | Pide a otra persona que lo apruebe |
| «Publicar exige un aprobador distinto del autor» | Quien redactó la versión fiscal intenta publicarla | Que la publique otra persona de Fiscal |
| «Este ajuste solo se cambia en el ámbito global» | Estás en una entidad y el ajuste es global | Cambia el ámbito a Global |
| «Sin permiso para cambiar el organigrama» | El `dip_actor` no es el titular | Usa el DIP del titular de la empresa |
| «Una unidad de tipo … necesita una unidad padre» | El tipo de unidad necesita un padre concreto | Indica la unidad superior, o deja el campo vacío para colgar de la Junta |
| «Supera el presupuesto…» | La concesión rebasa lo disponible | Reduce el importe o revisa el presupuesto |
| «Sin fondos suficientes» / «Cuenta de origen sin fondos» | No hay saldo en la cuenta que paga | Reduce el importe o espera a que haya fondos |
| «Un bono necesita fecha de caducidad» | Falta la caducidad en un bono | Pon la fecha o usa una convocatoria con caducidad |
| «No se puede conceder a una cuenta de la propia empresa» | Intentas conceder a una cuenta de la misma empresa | Elige otro beneficiario |
| «La convocatoria no está abierta hoy» | Fuera de sus fechas o cerrada | Revisa las fechas o reábrela (si la regla lo permite) |
| «La fecha de la transferencia está en el pasado» | La fecha programada ya pasó | Pon una fecha futura |
| «No se ha podido cargar» | Fallo al leer datos | Pulsa **Reintentar**; si persiste, avisa con el texto |

---

## 13. Límites conocidos (lo que todavía no hace o no está verificado)

- Las pantallas del panel **no se han probado en un navegador real**. La verificación confirma que el código compila, no el aspecto ni el orden exacto de los botones.
- Las **deudas cobradas tras una reversión** se recuperan, pero **no se vuelven a autorizar** salvo que la convocatoria lo permita (apartado 5.5).
- Las **convocatorias de una empresa** solo son visibles para la entidad y la Junta. Las empresas no tienen pantalla propia: operan por la API de banca.
- Los **recibos** en PDF son de texto simple: sin logotipo ni formato legal.
- La **subida de logotipos** valida la estructura del archivo, pero no lo re-codifica ni lo analiza con antivirus.
- Nada de esto se ha ejecutado todavía en la base de datos de producción.

---

## 14. Dónde mirar más

- `docs/openapi.json`: todas las rutas públicas, sus parámetros y ejemplos.
- `docs/FLUJOS.md`: diagramas de cada flujo.
- `docs/ADR-*.md` (en `docs/decisions/`): por qué el sistema funciona como funciona.
- `docs/NOMINA_NEXE.md`, `docs/DISPUTAS.md`, `docs/LIQUIDACION.md`, `docs/IDEMPOTENCIA.md`: detalle de cada área.
- `CHANGELOG.md`: qué ha cambiado en cada versión.
