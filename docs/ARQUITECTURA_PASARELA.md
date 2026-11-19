# Arquitectura de la pasarela de pago (Placeta One)

Los diagramas están en formato Mermaid. Se ven en GitHub, en VS Code (extensión Markdown Preview Mermaid) y en la mayoría de wikis.

## 1. Producto: la pasarela es un producto por banco

```mermaid
flowchart LR
  P[Producto Pasarela<br/>contratado por cada banco] --> C[Clientes: cuentas de empresa<br/>e institucionales]
  P --> M[Medios de pago]
  P --> R[Restricciones del banco]
  P --> K[Comisiones]
  P --> A[Aviso al cliente]
  M --> M1[Cuenta]
  M --> M2[Tarjeta: débito, crédito o prepago]
  R --> R1[Medio: cuenta o tarjeta]
  R --> R2[Tipo de tarjeta]
  R --> R3[Modalidad: inmediata o diferida]
  R --> R4[Operación: interbancario]
  K --> K1[Tarifa fija o porcentaje<br/>fijada por el propietario]
  K --> K2[Quién cobra: propietario o banco pagador]
  K --> K3[Quién paga: cliente o banco<br/>decidido por el banco, por producto]
  A --> A1["Tu entidad de pagos del ecosistema Placeta<br/>puede aplicar otras comisiones extra a las mostradas."]
```

## 2. Flujo de un pago con código

```mermaid
sequenceDiagram
  autonumber
  participant C as Comercio (cuenta de empresa)
  participant P as Placeta (pasarela)
  participant K as Cliente
  participant B as Banco del pagador
  C->>P: Crear pago (importe, destino, DIP, cuenta o tarjeta)
  P->>P: Comprueba producto, restricciones y comisión
  P-->>C: Código PAG-XXXX-XXXX-XXXX-XXXX, comisión, total y aviso
  P->>B: Aviso checkout.confirmacion_requerida
  C->>K: Muestra el código
  K->>B: Introduce el código en su app o banca online
  B->>P: Canjear código (código, DIP del cliente)
  P-->>B: Detalle del pago (importe, comisión, aviso, bloqueos)
  K->>B: Aprueba con su autenticación del banco
  B->>P: Resolución aprobado
  P->>P: Vuelve a comprobar restricciones y cobra (cuenta o tarjeta) y comisión
  P-->>C: Webhook checkout.pagado
  P-->>B: Webhook checkout.pagado
```

Placeta no abre ninguna sesión propia del cliente ni pide credenciales. La sesión la tiene el banco.

## 3. Organigrama institucional (ejemplo: Grupo de La Placeta)

```mermaid
flowchart TD
  G[Grupo de La Placeta] --> E[Entidad titular de la cuenta<br/>CIP-00000001]
  E --> J[Junta · 5 puestos]
  E --> AD[Administración · gestión operativa]
  AD --> PA[Presidencia y Administración]
  AD --> EH[Economía y Hacienda]
  AD --> CO[Comunicaciones · 45.000 Pz]
  AD --> EC[Educación y Comunidad]
  AD --> JU[Juventud]
  AD --> AE[Actividades y Eventos]
  AD --> TI[Tecnología e Innovación]
  CO --> RL[Proyecto: Radio La Placeta · 15.000 Pz]
  CO --> PC[Proyecto: Publicaciones y campañas · 12.000 Pz]
  CO --> CI[Proyecto: Comunicación institucional · 10.000 Pz]
  CO --> OP[Proyecto: Otras actividades · 8.000 Pz]
  E --> IN[Instituciones internas]
  AD --> UC[Unidad de control económico]
```

El presupuesto de un proyecto se descuenta de su departamento y de la entidad sin duplicarse.

## 4. Modelo de datos (esquema)

```mermaid
erDiagram
  PLONE27_BANKS ||--o{ PLONE27_RESTRICCIONES_PAGO : configura
  PLONE27_BANKS ||--o| PLONE27_COMISIONES_BANCO : tarifa
  PLONE27_BANKS ||--o{ PLONE27_POLITICA_COMISION : decide
  PLONE27_ACCOUNTS ||--o{ PLONE27_CHECKOUTS : paga
  PLONE27_ACCOUNTS ||--o{ PLONE27_CARDS : tiene
  PLONE27_CARDS ||--o{ PLONE27_CHECKOUTS : usada_en
  PLONE27_API_CLIENTS ||--o{ PLONE27_CHECKOUTS : crea
  PLONE27_ENTIDADES ||--o{ PLONE27_UNIDADES : organiza
  PLONE27_UNIDADES ||--o{ PLONE27_UNIDADES : depende_de
  PLONE27_UNIDADES ||--o{ PLONE27_PUESTOS : contiene
  PLONE27_PUESTOS ||--o{ PLONE27_NOMBRAMIENTOS : ocupa
  PLONE27_PERSONAS ||--o{ PLONE27_NOMBRAMIENTOS : tiene
  PLONE27_UNIDADES ||--o{ PLONE27_PRESUPUESTOS : asigna
  PLONE27_UNIDADES ||--o{ PLONE27_GASTOS : imputa
  PLONE27_UNIDADES ||--o{ PLONE27_FONDOS : reserva
  PLONE27_ENTIDADES ||--o{ PLONE27_CONVOCATORIAS : convoca
  PLONE27_UNIDADES ||--o{ PLONE27_SOLICITUDES_UNIDAD : pide
  PLONE27_PLANES_PLURIANUALES }o--|| PLONE27_UNIDADES : sobre
  PLONE27_CHECKOUTS {
    uuid id
    text codigo_hash
    text medio
    numeric comision
    text comision_pagador
    text comision_beneficiario
    text estado
  }
  PLONE27_RESTRICCIONES_PAGO {
    uuid bank_id
    text tipo
    text valor
    boolean bloqueado
  }
```

## 5. Qué configura cada parte

| Quién | Qué configura | Dónde |
|---|---|---|
| Propietario de la pasarela | Tarifa por banco (fija o en porcentaje) y quién cobra la comisión | Panel: API de comisiones del propietario |
| Banco | Quién paga la comisión en cuentas y en tarjetas | API `PUT /api/v1/bk/comisiones` |
| Banco | Restricciones: medios, tipos de tarjeta, modalidades y operaciones | API `PUT /api/v1/bk/restricciones` |
| Banco | Canje de códigos y resolución de pagos | API `/api/v1/bk/pagos/...` |
| Comercio | Crear pagos y mostrar el código | API `POST /api/v1/bk/checkouts` |

## 6. Pendiente de decidir

- Si la ventana de pago web se mantiene como alternativa al código o se retira.
- Si las restricciones también se aplican al lado del comercio (por ejemplo, prohibir cobrar con tarjeta de crédito).
- El precio y las condiciones del producto por banco.
