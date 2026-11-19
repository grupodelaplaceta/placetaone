# 01 · Backend del banco

Tu backend es el único que conoce la clave `x-api-key` y el secreto de firma. Es también quien autentica a tus clientes y decide cuándo abrir una sesión en Placeta.

## Configuración

Variables de entorno (nunca en el código ni en el repositorio):

```
PLACETA_BASE=https://api.placeta.example
PLACETA_CLAVE=plk_...          # clave de tu cliente
PLACETA_FIRMA=...              # secreto de firma de tu cliente
```

Instala el SDK (copia la carpeta `sdk/` en tu proyecto) y crea un cliente de servidor:

```ts
// lib/placeta.ts  (solo servidor)
import { PlacetaServidor } from "../sdk/placeta-servidor";

export const placeta = new PlacetaServidor(
  process.env.PLACETA_BASE!,
  process.env.PLACETA_CLAVE!,
  process.env.PLACETA_FIRMA!,
);
```

## Flujo 1 · Iniciar sesión de un cliente

Tu sistema autentica a la persona (contraseña, MFA, lo que uses). Solo entonces pides a Placeta un token para ella. El DIP es el identificador de la persona en Placeta.

```ts
// app/api/banca/sesion/route.ts  (Next.js, ejemplo)
import { placeta } from "@/lib/placeta";
import { cookies } from "next/headers";
import { PlacetaError } from "../../../../sdk/placeta-core";

export async function POST(req: Request) {
  const { usuario, clave } = await req.json();
  const cliente = await verificarEnTuSistema(usuario, clave);   // tu autenticación
  if (!cliente) return Response.json({ error: "Credenciales no válidas" }, { status: 401 });

  try {
    const sesion = await placeta.crearSesion(cliente.dip, {
      minutos: 15,
      permisos: ["me:read", "me:transfer"],          // solo lo que necesita la app
    });
    // Guarda el token en TU almacén de sesiones del servidor, asociado a una cookie de tu banco.
    await guardarSesionPlaceta(cliente.id, sesion.token, sesion.expira);
    (await cookies()).set("banca_sesion", await crearSesionBanco(cliente.id), {
      httpOnly: true, secure: true, sameSite: "strict", path: "/", maxAge: 60 * 60 * 8,
    });
    return Response.json({ ok: true });
  } catch (e) {
    if (e instanceof PlacetaError && e.status === 403) return Response.json({ error: "Permiso no concedido" }, { status: 403 });
    throw e;   // error inesperado: lo ve tu monitorización
  }
}
```

`verificarEnTuSistema`, `guardarSesionPlaceta` y `crearSesionBanco` son tuyos: no los da Placeta.

## Flujo 2 · Renovar la sesión de Placeta

La sesión dura 15 minutos por defecto (máximo 60). Renuévala **antes** de que caduque, desde el backend, creando una nueva:

```ts
async function tokenVigente(clienteId: string): Promise<string> {
  const sesion = await leerSesionPlaceta(clienteId);          // tu almacén
  if (sesion && new Date(sesion.expira).getTime() - Date.now() > 60_000) return sesion.token;
  const nueva = await placeta.crearSesion((await leerCliente(clienteId)).dip, { minutos: 15 });
  await guardarSesionPlaceta(clienteId, nueva.token, nueva.expira);
  return nueva.token;
}
```

## Flujo 3 · Cerrar sesión

```ts
import { PlacetaUsuario } from "../../../sdk/placeta-usuario";
// al cerrar sesión en tu banco:
await new PlacetaUsuario(process.env.PLACETA_BASE!, token).cerrarSesion();
await borrarSesionPlaceta(clienteId);
```

## Flujo 4 · Dar de alta a un cliente en sus cuentas

Cuando una persona abre una cuenta en tu entidad, vincúlala por su DIP. Solo puedes vincular cuentas de tu entidad.

```ts
await placeta.vincularCuenta("12345678Z", "PZ-0001-0002", "holder");
```

Roles: `holder` (titular: todo), `coholder` (cotitular: puede mover dinero), `authorized` (autorizada: solo lectura).

## Flujo 5 · Buscar por DIP (operaciones de tu personal)

Tu personal puede buscar a una persona por su DIP para ver sus cuentas **en tu entidad**:

```ts
const cuentas = await placeta.buscarPorDip("12.345.678-z");   // se normaliza solo
```

La respuesta es la misma si el DIP no existe o si no tiene cuentas en tu banco. No la uses para comprobar en qué otros bancos está una persona: no puedes, y no está pensada para eso.

## Flujo 6 · Orígenes de navegador (solo si usas llamada directa)

```ts
await placeta.solicitarOrigen("https://app.tubanco.es");   // queda pendiente de aprobación
const origenes = await placeta.origenes();                   // ver su estado
```

## Checklist del backend

- [ ] Clave y secreto solo en variables de entorno del servidor.
- [ ] La sesión de Placeta se crea **después** de autenticar a la persona en tu sistema.
- [ ] El token de Placeta nunca se envía al navegador en el patrón BFF.
- [ ] Renovación de sesión antes de caducar, desde el servidor.
- [ ] Permisos mínimos en cada sesión.
- [ ] Logs sin DIP ni tokens; si necesitas trazabilidad, usa el hash que devuelve la auditoría.
