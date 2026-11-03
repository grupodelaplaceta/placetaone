#!/usr/bin/env python3
"""Comprobación estática del SQL de instalación. No necesita PostgreSQL.
Detecta: bloques $$ anidados, $$ sin cerrar, paréntesis desbalanceados y más de una transacción.
Uso: python3 sql_estatico.py ARCHIVO.sql   (código de salida 0 = sin errores)"""
import re, sys
def revisar(ruta):
    s = open(ruta, encoding="utf-8").read()
    code = re.sub(r"--[^\n]*", "", s)              # quitar comentarios de línea
    errores = []
    # 1) bloques $$: un "do $$" o "as $$" nunca debe aparecer dentro de otro bloque $$
    estado = 0; abre = None
    for m in re.finditer(r"\$\$", code):
        linea = code.count("\n", 0, m.start()) + 1
        previo = code[max(0, m.start() - 4):m.start()]
        if estado == 1 and re.search(r"\b(do|as)\s*$", previo):
            errores.append(f"línea {linea}: bloque $$ anidado dentro del bloque abierto en la línea {abre}")
        if estado == 0: abre = linea
        estado ^= 1
    if estado == 1: errores.append(f"bloque $$ sin cerrar (abierto en la línea {abre})")
    # 2) paréntesis, sin contar el texto entre comillas simples
    sin_cadenas = re.sub(r"\'(?:[^\']|\'\')*\'", "''", code)
    if sin_cadenas.count("(") != sin_cadenas.count(")"): errores.append("paréntesis desbalanceados")
    # 3) una sola transacción
    if s.count("\nbegin;") > 1 or s.count("\ncommit;") > 1: errores.append("más de un begin/commit")
    return errores
if __name__ == "__main__":
    e = revisar(sys.argv[1])
    for x in e: print("ERROR SQL:", x)
    print("SQL estático:", "sin errores" if not e else f"{len(e)} error(es)")
    sys.exit(1 if e else 0)
