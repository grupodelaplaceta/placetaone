#!/usr/bin/env python3
"""Comprobación previa al despliegue. Uso: python3 verificacion/preflight.py <raíz del proyecto>
Revisa: variables de entorno obligatorias, migraciones, instalación completa y pruebas de base de datos.
No sustituye a la prueba en una base de pruebas (verificacion/pruebas_db.sql)."""
import os, sys, glob, subprocess, re

raiz = sys.argv[1] if len(sys.argv) > 1 else "."
fallos = []

obligatorias = ["NEXT_PUBLIC_SUPABASE_URL", "NEXT_PUBLIC_SUPABASE_ANON_KEY", "SUPABASE_SERVICE_ROLE_KEY",
                "CRON_SECRET", "WEBHOOK_KEY", "PLACETA_PUBLIC_URL"]
for v in obligatorias:
    if not os.environ.get(v): fallos.append(f"Falta la variable de entorno {v}")
if os.environ.get("WEBHOOK_KEY") and len(os.environ["WEBHOOK_KEY"]) < 24:
    fallos.append("WEBHOOK_KEY debe tener al menos 24 caracteres")
if os.environ.get("CRON_SECRET") and len(os.environ["CRON_SECRET"]) < 24:
    fallos.append("CRON_SECRET debe tener al menos 24 caracteres")

migs = sorted(glob.glob(os.path.join(raiz, "supabase/migrations/*.sql")))
if len(migs) != 43: fallos.append(f"Se esperaban 43 migraciones y hay {len(migs)}")

setup = os.path.join(raiz, "supabase/setup/plone27_setup_completo.sql")
if not os.path.exists(setup): fallos.append("Falta supabase/setup/plone27_setup_completo.sql (ejecutar el generador)")
elif "create table if not exists plone27_parametros" not in open(setup, encoding="utf-8").read():
    fallos.append("La instalación completa no incluye la migración 0043")

if not os.path.exists(os.path.join(raiz, "verificacion/pruebas_db.sql")): fallos.append("Falta verificacion/pruebas_db.sql")

r = subprocess.run([sys.executable, os.path.join(raiz, "verificacion/sql_estatico.py"), setup], capture_output=True, text=True)
if r.returncode != 0: fallos.append("La instalación completa no pasa la revisión estática: " + r.stdout.strip()[:200])

print("PREFLIGHT:", "sin incidencias." if not fallos else f"{len(fallos)} incidencia(s):")
for f in fallos: print("  -", f)
sys.exit(1 if fallos else 0)
