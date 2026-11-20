# Flujos de Placeta One

Cada flujo tiene un diagrama y una explicación. Los diagramas se ven en GitHub y en cualquier visor de Markdown con soporte de Mermaid.

## 1. Quién hace qué

```mermaid
flowchart LR
  J["Junta (rol admin)"] -->|gestiona| P["Panel de administración"]
  E["Entidad (banco)"] -->|opera por| API["API de banca"]
  P --> SYS[(Placeta One)]
  API --> SYS
  U["Usuario o beneficiario"] -->|usa| APP["App y tarjeta"]
  APP --> SYS
  SYS -->|mueve dinero solo con| R["Reglas: límites, doble firma, presupuesto"]
```

**Qué significa.** La Junta gestiona el sistema desde el panel. Cada entidad (banco) opera sus propios clientes, empresas y programas por la API de banca, y no ve los de otra entidad. Los usuarios usan la app y la tarjeta. Todo movimiento de dinero pasa por las reglas del sistema.

## 2. Pago con pasarela (checkout)

```mermaid
sequenceDiagram
  participant C as Comercio
  participant P as Placeta
  participant U as Usuario
  participant B as Banco pagador
  C->>P: Crea un checkout (importe, comercio)
  P-->>C: Código de pago PAG-XXXX
  U->>P: Introduce el código
  P->>B: Pide canje y resolución
  B-->>P: Aprueba o rechaza
  alt Aprobado
    P->>C: Abona al comercio (menos comisiones)
  else Rechazado
    P-->>U: Pago rechazado, sin cargo
  end
```

**Qué significa.** El comercio crea un cobro y recibe un código. El usuario lo introduce y el banco del pagador decide si aprueba. Solo si aprueba se abona al comercio, descontando las comisiones configuradas. Un rechazo no mueve dinero.

## 3. RBU semanal: emisión, canje y caducidad

```mermaid
flowchart TD
  A["Emisión semanal"] --> B["Bono de la semana<br/>caduca a los 3 meses"]
  B --> C{"¿Se canjea antes de caducar?"}
  C -->|Sí| D["Saldo a la cuenta principal<br/>no caduca"]
  C -->|No| E["Bono caducado<br/>no sale dinero de la Reserva"]
```

**Qué significa.** Cada semana se emite un bono por usuario. Tiene tres meses para canjearse. Si se canjea, el saldo pasa a la cuenta principal y ya no caduca, se gaste o no. Si no se canjea, caduca y no sale ni un céntimo de la Reserva.

## 4. Subvención: del alta al abono

```mermaid
flowchart TD
  A["Conceder"] --> B{"¿Fondos y presupuesto suficientes?"}
  B -->|No| X["Rechazada: no se crea"]
  B -->|Sí| C["Reserva el importe en la cuenta del programa"]
  C --> D["Justificar: gasto elegible de la cuenta del beneficiario"]
  D --> E["Aprobar y pagar"]
  E --> F["Abono: consume la reserva"]
  C --> G{"¿Caduca antes de usarse?"}
  G -->|Sí| H["Caducada: se libera la reserva"]
  F --> I{"¿Se revierte el abono?"}
  I -->|No| J["Completada"]
  I -->|Sí| K["Reversión"]
```

**Qué significa.** Conceder reserva el dinero antes de nada, así que el presupuesto siempre está protegido. Justificar y abonar consumen esa reserva. Si la subvención caduca antes de usarse, la reserva se libera. Una reversión se trata en el flujo 5.

## 5. Reversión de un abono

```mermaid
flowchart TD
  R["Revertir abono"] --> S{"¿El beneficiario tiene saldo?"}
  S -->|Sí| T["Reversión completa: el dinero vuelve al programa"]
  S -->|No| U["Devuelve lo disponible"]
  U --> V["Lo que falta queda como deuda del beneficiario"]
  V --> W["Cobro automático de la deuda"]
  W --> Y{"¿La convocatoria permite reautorizar?"}
  Y -->|Sí| Z["Lo cobrado vuelve a quedar reservado"]
  Y -->|No| Q["Lo cobrado se recupera sin reserva"]
```

**Qué significa.** Revertir nunca deja saldo negativo. Si el beneficiario tiene saldo, la reversión es completa. Si no, lo disponible vuelve de inmediato y el resto se convierte en deuda, que el sistema cobra cuando el beneficiario tenga fondos. Lo cobrado solo se reautoriza si la convocatoria está abierta y lo permite.

## 6. Cambio de ajustes con doble firma

```mermaid
sequenceDiagram
  participant A as Persona A
  participant S as Sistema
  participant B as Persona B
  A->>S: Propone un cambio con motivo
  S-->>S: Queda pendiente
  alt B aprueba
    B->>S: Aprueba
    S->>S: Aplica el cambio y lo registra
  else B rechaza
    B->>S: Rechaza
    S->>S: Descarta el cambio
  end
  Note over A,B: A no puede aprobar su propio cambio
```

**Qué significa.** Un cambio de ajuste lo propone una persona y lo aprueba otra. Nadie se aprueba a sí mismo, ni siquiera el admin. Cada paso queda en la auditoría con su motivo.

## 7. Publicar una versión fiscal

```mermaid
stateDiagram-v2
  [*] --> Borrador: quien redacta la crea
  Borrador --> Publicada: otra persona la publica
  Borrador --> [*]: se descarta
  Publicada --> [*]
  note right of Publicada
    Entra en vigor en la fecha indicada.
    Queda fijada con su huella de integridad.
  end note
```

**Qué significa.** Una versión fiscal nace como borrador de quien la redacta. Para entrar en vigor la publica otra persona. Una vez publicada queda fijada con una huella que permite comprobar que no se ha cambiado.

## 8. Empresa, entidad, organigrama y nómina

```mermaid
flowchart LR
  A["Alta de empresa"] --> B["Primera cuenta de empresa"]
  B --> C["Entidad institucional (CIP)<br/>se crea sola"]
  C --> D["Organigrama inicial<br/>Junta, puesto de titular, nombramiento"]
  D --> E["Complementos de actividad<br/>asignados al contrato"]
  E --> F["Pago del periodo<br/>salario + complementos"]
  F --> G["NEXE: conceptos y recibos"]
```

**Qué significa.** Al dar de alta una empresa y añadirle una cuenta, su entidad institucional se crea sola, con un organigrama inicial para que el titular pueda empezar. Sobre cada contrato se asignan complementos de actividad. El pago del periodo incluye salario y complementos, y NEXE lee los conceptos y los recibos.

## 9. Deuda: cobro automático

```mermaid
flowchart TD
  D["Deuda con vencimiento"] --> E{"¿Hay disputa abierta?"}
  E -->|Sí| P["No se cobra hasta resolverla"]
  E -->|No| F{"¿Saldo disponible?"}
  F -->|Sí| C["Cobro automático"]
  F -->|No| W["Espera al siguiente ciclo"]
  C --> T{"¿Pagada del todo?"}
  T -->|Sí| OK["Cerrada"]
  T -->|No| W
```

**Qué significa.** Una deuda se cobra sola cuando vence, si no hay disputa abierta y hay saldo. Si no hay saldo, espera al siguiente ciclo diario. Una disputa la detiene hasta que se resuelva.

## 10. Convocatoria de una empresa

```mermaid
flowchart TD
  A["El titular abre la convocatoria"] --> B{"¿Destino?"}
  B -->|todos| C["Beneficiarios de la entidad"]
  B -->|empresa| D["Solo la empresa indicada"]
  C --> E["Concede: reserva el importe en la cuenta de fondos"]
  D --> E
  E --> F{"¿Cuenta de la propia empresa?"}
  F -->|Sí| X["Rechazada: autoconcesión"]
  F -->|No| G["Concesión activa"]
  G --> H{"¿Caduca antes de usarse?"}
  H -->|Sí| I["Caducada: se libera la reserva"]
```

**Qué significa.** La empresa abre la convocatoria y elige el destino. Cada concesión reserva su importe en la cuenta de fondos de la propia empresa. Nunca se puede conceder a una cuenta de la empresa misma. Lo no usado caduca y se libera.

## Cómo validar estos diagramas

Cada bloque `mermaid` se extrae a un archivo `.mmd` y se renderiza con el CLI de Mermaid:

```bash
mmdc -i flujo.mmd -o flujo.svg   # debe terminar sin errores y generar el SVG
```

Un diagrama que no se renderiza no se publica.
