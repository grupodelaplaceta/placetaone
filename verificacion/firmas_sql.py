#!/usr/bin/env python3
"""Funciones que cambian de firma (argumentos o tipo devuelto) a lo largo de la instalación.
Esas funciones deben borrarse al principio de plone27_setup_completo.sql, porque una base que ya tiene
una versión anterior falla con 42P13 / 'cannot change return type'. Uso: python3 verificacion/firmas_sql.py <raíz>"""
import re, sys, os
raiz = sys.argv[1] if len(sys.argv) > 1 else "."
s = open(os.path.join(raiz, "supabase/setup/plone27_setup_completo.sql"), encoding="utf-8").read()
code = re.sub(r"--[^\n]*", "", s)
def norm(x): return " ".join(x.split()).lower()
firmas = {}
for m in re.finditer(r"create or replace function (plone27_\w+)\s*\(", code):
    i = m.end(); d = 1; j = i
    while d:
        d += 1 if code[j] == "(" else (-1 if code[j] == ")" else 0); j += 1
    args = norm(code[i:j-1])
    ret = re.search(r"returns\s+(.*?)\s+language", code[j:j+400], re.S | re.I)
    clave = (args, norm(ret.group(1)) if ret else "")
    firmas.setdefault(m.group(1), set()).add(clave)
cambian = sorted(n for n, v in firmas.items() if len(v) > 1)
bloque = re.search(r"-- Antes de crear nada.*?end \$\$;", s, re.S)
listados = set()
if bloque:
    arr = re.search(r"array\[(.*?)\]", bloque.group(0), re.S | re.I)
    if arr: listados = set(re.findall(r"'(plone27_\w+)'", arr.group(1)))
faltan = [n for n in cambian if n not in listados]
print("funciones con firma cambiante:", ", ".join(cambian) or "ninguna")
if faltan:
    print("FALTAN en el borrado inicial de plone27_setup_completo.sql:", ", ".join(faltan)); sys.exit(1)
print("todas están en el borrado inicial.")
