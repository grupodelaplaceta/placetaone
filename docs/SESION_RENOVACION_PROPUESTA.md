# Renovación de sesión desde el usuario: PROPUESTA (pendiente de tu aprobación)

No está implementada. Es una decisión de seguridad, y la tomas tú.

## Situación actual
- Solo el banco abre sesiones (`POST /api/v1/sessions`, firmada con `signing_secret`).
- El token del usuario (`pus_…`) dura hasta 60 minutos y no se puede renovar.
- Para seguir, el banco tiene que volver a pedir una sesión, con su propia firma.

## Propuesta
1. **Token de renovación** que se devuelve junto con el token de acceso, al abrir la sesión.
2. **Duración del token de renovación:** 30 días. El token de acceso sigue durando 15 minutos (no 60).
3. **Rotación:** cada renovación entrega un token de renovación nuevo y invalida el anterior.
4. **Detección de reutilización:** si se presenta un token de renovación ya usado, se revoca toda la familia de sesiones de ese usuario y ese cliente. Señal de robo.
5. **Ligado al cliente:** el token de renovación solo vale para el cliente que abrió la sesión.
6. **Revocación:** el banco puede revocar sesiones con su firma; el usuario puede cerrar las demás sesiones (ya existe).
7. **Sin escalar permisos:** la renovación nunca da más permisos que la sesión original.

## Qué cambia en el código
- Columna de hash del token de renovación y de su fecha de caducidad, y un identificador de familia.
- `POST /api/v1/sessions` devuelve también el token de renovación.
- Nueva ruta `POST /api/v1/me/sesion/renovar` que rota los dos tokens.

## Decisiones que necesito de ti
- ¿Aceptas los 30 días de renovación y los 15 minutos de acceso?
- ¿Quieres que el banco pueda desactivar la renovación para sus clientes, o lo fuerza Placeta?
