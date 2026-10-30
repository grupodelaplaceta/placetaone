#!/usr/bin/env bash
# Verificación automática de Placeta One. Ejecútalo desde la raíz del proyecto:  bash verificacion/ejecutar.sh
# Requisitos: Node 18+ y TypeScript (npm i -D typescript tsx). Opcional: psql y DATABASE_URL (para el SQL) y las variables del script de aislamiento.
# Cada paso informa si pasa o falla; el código de salida es 0 solo si todos los pasos obligatorios pasan.
cd "$(dirname "$0")"
TSC="${TSC:-npx tsc}"; TSX="${TSX:-npx tsx}"
fallos=0
paso() { echo; echo "== $1"; }
paso "1/5 Tipos del SDK (estricto)";        $TSC -p tsconfig.sdk.json  && echo "OK" || { echo "FALLO"; fallos=$((fallos+1)); }
paso "2/5 Tipos de la API y librerías";     $TSC -p tsconfig.api.json  && echo "OK" || { echo "FALLO"; fallos=$((fallos+1)); }
paso "3/5 Tipos de las pantallas (React)";  $TSC -p tsconfig.ui.json   && echo "OK" || { echo "FALLO"; fallos=$((fallos+1)); }
paso "4/5 Comportamiento del SDK (simulador)"; $TSX sdk.test.ts && echo "OK" || { echo "FALLO"; fallos=$((fallos+1)); }
paso "5/5 SQL en PostgreSQL";
if [ -n "${DATABASE_URL:-}" ] && command -v psql >/dev/null; then
  psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -q -f ../supabase/setup/plone27_setup_completo.sql && echo "OK" || { echo "FALLO"; fallos=$((fallos+1)); }
  if [ -n "${IBAN_A:-}" ] && [ -n "${IBAN_B:-}" ] && [ -n "${DIP_A:-}" ] && [ -n "${DIP_B:-}" ] && [ -n "${CLAVE:-}" ] && [ -n "${FIRMA:-}" ] && [ -n "${BASE:-}" ]; then
    echo "-- aislamiento entre usuarios"; node ../scripts/aislamiento.mjs || fallos=$((fallos+1))
  else
    echo "(aislamiento omitido: faltan BASE, CLAVE, FIRMA, IBAN_A, IBAN_B, DIP_A, DIP_B)"
  fi
else
  echo "OMITIDO: define DATABASE_URL y ten psql instalado para aplicar y probar el SQL."
  fallos=$((fallos+0))
fi
echo; if [ $fallos -eq 0 ]; then echo "VERIFICACIÓN: todos los pasos obligatorios pasan."; else echo "VERIFICACIÓN: $fallos paso(s) fallan."; fi
exit $fallos
