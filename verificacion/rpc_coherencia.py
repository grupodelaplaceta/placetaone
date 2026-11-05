#!/usr/bin/env python3
"""Coherencia de llamadas RPC: cada rpc("plone27_…", {...}) debe enviar solo parámetros que la función SQL acepta
y cubrir los que no tienen valor por defecto.
p_actor lo fija el servidor en las puertas de administración (/api/rpc/[fn] y las rutas de admin),
así que en esos casos se da por enviado. Uso: python3 verificacion/rpc_coherencia.py <raiz del proyecto>"""
import re, sys, glob, os

root = sys.argv[1] if len(sys.argv) > 1 else "."
sql = open(os.path.join(root, "supabase/setup/plone27_setup_completo.sql"), encoding="utf-8").read()
code = re.sub(r"--[^\n]*", "", sql)

def split_args(s):
    out, d, cur = [], 0, ""
    for ch in s:
        if ch == "(": d += 1
        if ch == ")": d -= 1
        if ch == "," and d == 0:
            out.append(cur); cur = ""
        else:
            cur += ch
    if cur.strip(): out.append(cur)
    return out

firmas = {}  # nombre -> (parámetros, obligatorios); gana la última definición
for m in re.finditer(r"create or replace function (plone27_\w+)\s*\(", code):
    i = m.end(); d = 1; j = i
    while d:
        d += 1 if code[j] == "(" else (-1 if code[j] == ")" else 0); j += 1
    params, req = set(), set()
    for a in split_args(code[i:j-1]):
        mm = re.match(r"\s*(p_\w+)", a)
        if not mm: continue
        params.add(mm.group(1))
        if not re.search(r"\bdefault\b", a, re.I): req.add(mm.group(1))
    firmas[m.group(1)] = (params, req)

problemas, n = [], 0
for f in glob.glob(os.path.join(root, "src/**/*.ts*"), recursive=True):
    s = open(f, encoding="utf-8").read()
    gateway = f.endswith(".tsx") or "/api/rpc/" in s
    rel = os.path.relpath(f, root)
    for m in re.finditer(r"rpc\(\s*[\"'](plone27_\w+)[\"']\s*,\s*\{", s):
        n += 1
        fn = m.group(1); i = m.end() - 1; depth = 0; j = i
        while True:
            c = s[j]
            if c == "{": depth += 1
            elif c == "}":
                depth -= 1
                if depth == 0: break
            j += 1
        keys = set(re.findall(r"(p_\w+)\s*:", s[i:j+1]))
        if fn not in firmas:
            problemas.append((rel, fn, "función inexistente")); continue
        params, req = firmas[fn]
        if gateway: keys.add("p_actor")
        extra, falta = keys - params, req - keys
        if extra or falta: problemas.append((rel, fn, sorted(extra), sorted(falta)))

print(f"llamadas RPC revisadas: {n} | incoherencias: {problemas or 'ninguna'}")
sys.exit(1 if problemas else 0)
