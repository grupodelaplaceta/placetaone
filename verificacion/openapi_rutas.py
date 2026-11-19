#!/usr/bin/env python3
"""Comprueba que la documentación (OpenAPI) y las rutas reales de la API coinciden.
Errores: ruta sin documentar, documentación de una ruta inexistente, operación sin resumen,
sin grupo, sin ejemplo de respuesta 2xx, webhooks sin ejemplo, o public/openapi.json distinto del original.
Uso: python3 openapi_rutas.py --openapi ../docs/openapi.json --api ../src/app/api --publico ../public/openapi.json"""
import argparse, glob, json, os, re, sys
EXCLUIR = ("admin", "cron", "rpc")
RAIZ_EXCLUIDA = ("public-config", "transfers", "accounts")   # rutas de personal, no de la API pública

def rutas_reales(api):
    out = set()
    for f in glob.glob(os.path.join(api, "**", "route.ts"), recursive=True):
        rel = os.path.relpath(os.path.dirname(f), api)
        if rel.split(os.sep)[0] in EXCLUIR or rel in RAIZ_EXCLUIDA: continue
        path = "/api/" + rel.replace(os.sep, "/").replace("[", "{").replace("]", "}")
        for m in re.findall(r"export async function (GET|POST|PUT|PATCH|DELETE)\b", open(f, encoding="utf-8").read()):
            out.add((path, m))
    return out

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--openapi", required=True); ap.add_argument("--api", required=True); ap.add_argument("--publico", required=True); ap.add_argument("--scopes", default=None)
    a = ap.parse_args()
    errores = []
    spec = json.load(open(a.openapi, encoding="utf-8"))
    doc = {(p, m.upper()) for p, ops in spec["paths"].items() for m in ops}
    real = rutas_reales(a.api)
    for p, m in sorted(real - doc): errores.append(f"ruta sin documentar: {m} {p}")
    for p, m in sorted(doc - real): errores.append(f"documentada pero no existe: {m} {p}")
    for p, ops in spec["paths"].items():
        for m, op in ops.items():
            etiqueta = f"{m.upper()} {p}"
            if not op.get("summary"): errores.append(f"sin resumen: {etiqueta}")
            if not op.get("x-grupo"): errores.append(f"sin grupo: {etiqueta}")
            ok = [v for k, v in op.get("responses", {}).items() if k.startswith("2")]
            if not any("content" in v and "example" in v["content"].get("application/json", {}) for v in ok):
                errores.append(f"sin ejemplo de respuesta 2xx: {etiqueta}")
    for nombre, h in spec.get("x-webhooks", {}).items():
        ej = h.get("example", {})
        if not ("event" in ej and "data" in ej): errores.append(f"webhook sin ejemplo válido: {nombre}")
    if not spec.get("x-webhooks"): errores.append("falta x-webhooks")
    if open(a.openapi, "rb").read() != open(a.publico, "rb").read():
        errores.append("public/openapi.json no coincide con docs/openapi.json (copiar de nuevo)")
    if a.scopes:
        validos = set(re.findall(r'k: "([a-z:_]+)"', open(a.scopes, encoding="utf-8").read()))
        for p, ops in spec["paths"].items():
            for m, op in ops.items():
                x = op.get("x-permiso")
                if x and not x.startswith("me:") and x not in validos:
                    errores.append(f"permiso no registrado en scopes.ts: {x} ({m.upper()} {p})")
    print(f"rutas reales: {len(real)} · documentadas: {len(doc)} · webhooks: {len(spec.get('x-webhooks', {}))}")
    for e in errores: print("ERROR DOCUMENTACIÓN:", e)
    print("Documentación:", "sin errores" if not errores else f"{len(errores)} error(es)")
    return 1 if errores else 0

if __name__ == "__main__":
    sys.exit(main())
