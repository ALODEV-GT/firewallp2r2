#!/bin/bash
# Restaura en este equipo la sesión de Claude Code, su memoria y los archivos
# locales del proyecto. Ejecutar desde la raíz del repositorio:
#   bash sesion-claude/restaurar.sh
set -euo pipefail

SESION=871ecf25-eda1-4f3f-872b-85d16556a090
RUTA_ORIGINAL=/home/alodev/Documents/p2redes

REPO=$(git rev-parse --show-toplevel)
ORIGEN="$REPO/sesion-claude"
# Claude Code guarda cada proyecto en una carpeta cuyo nombre es la ruta del
# proyecto con los caracteres no alfanuméricos cambiados por guiones.
DESTINO="$HOME/.claude/projects/$(printf '%s' "$REPO" | sed 's/[^A-Za-z0-9]/-/g')"

mkdir -p "$DESTINO/memory"

# Transcripción de la sesión y resultados de herramientas.
if [[ -e "$DESTINO/$SESION.jsonl" ]]; then
  cp "$DESTINO/$SESION.jsonl" "$DESTINO/$SESION.jsonl.bak"
  echo "Ya existía una copia de la sesión; se guardó como $SESION.jsonl.bak"
fi
cp "$ORIGEN/$SESION.jsonl" "$DESTINO/"
cp -r "$ORIGEN/$SESION" "$DESTINO/"

# Si el repositorio está en otra ruta, la transcripción debe apuntar a la nueva.
if [[ "$REPO" != "$RUTA_ORIGINAL" ]]; then
  sed -i "s#$RUTA_ORIGINAL#$REPO#g" "$DESTINO/$SESION.jsonl"
  echo "Aviso: la ruta cambió de $RUTA_ORIGINAL a $REPO; se ajustó la transcripción."
fi

# Memoria del proyecto (no sobrescribe archivos que ya existan).
cp -n "$ORIGEN"/memory/*.md "$DESTINO/memory/"

# Archivo excluido de git a propósito: se restaura y se vuelve a excluir.
if [[ ! -e "$REPO/prompt-topologia-figma.md" ]]; then
  cp "$ORIGEN/archivos-locales/prompt-topologia-figma.md" "$REPO/"
fi
grep -qxF prompt-topologia-figma.md "$REPO/.git/info/exclude" \
  || echo prompt-topologia-figma.md >> "$REPO/.git/info/exclude"

# Memorias de engram de este proyecto.
if command -v engram >/dev/null 2>&1; then
  engram import "$ORIGEN/engram-p2redes.json"
else
  echo "engram no está instalado: se omitió la importación de sus memorias."
fi

echo
echo "Restauración terminada en: $DESTINO"
echo "Para continuar la sesión:"
echo "  cd $REPO && claude --resume $SESION"
