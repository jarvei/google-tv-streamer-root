#!/usr/bin/env bash
# reroot.sh — deja root otra vez en el Google TV Streamer tras un reinicio.
#
# Uso:
#   ./reroot.sh                 # espera arranque, reintenta hasta MAX_ATTEMPTS y verifica
#   ./reroot.sh --status        # solo estado (no lanza el exploit)
#   ./reroot.sh --attempts 4    # cambia el número de intentos
#
# El capture gate de GhostLock es flaky: cuando falla NO escribe nada y SELinux
# sigue Enforcing, así que reintentar en el mismo arranque es seguro. Si tras un
# intento SELinux queda Permissive y no hay agente, el estado ya no es fiable:
# el script aborta y hay que reiniciar (un intento por arranque limpio).
set -u

DEV="${DEV:?export DEV=<streamer-ip>:5555}"
DIR="$(cd "$(dirname "$0")" && pwd)"
BUNDLE="$DIR/ghostlock-kirkwood-oneclick.sh"
PATCHED="${PATCHED:-/tmp/ghostlock-preserve.sh}"
REMOTE="/data/local/tmp/ghostlock-preserve.sh"
CLIENT="/data/local/tmp/.ghostlock-oneclick/kirkwood_root_sh"
READY="/data/local/tmp/root_agent_ready"
PERF_LOOPS="${PERF_LOOPS:-60000}"
SETTLE_US="${SETTLE_US:-120000}"
MAX_ATTEMPTS="${MAX_ATTEMPTS:-6}"
ATTEMPT_PAUSE="${ATTEMPT_PAUSE:-45}"
RUN_TIMEOUT="${RUN_TIMEOUT:-200}"
LOG="$DIR/logs/reroot-$(date +%Y%m%d-%H%M%S).log"

mkdir -p "$DIR/logs"
die() { echo "[!] $*"; exit 1; }

adb connect "$DEV" >/dev/null 2>&1 || true

state() {
  adb -s "$DEV" shell 'printf "boot="; getprop sys.boot_completed; printf "selinux="; getenforce; printf "system_server="; pidof system_server; printf "window="; service check window' 2>/dev/null | tr -d '\r'
}

root_uid() {
  local line name
  line="$(adb -s "$DEV" shell "cat $READY" 2>/dev/null | tr -d '\r')"
  name="$(printf '%s\n' "$line" | sed -n 's/.*abstract=\([^ ]*\).*/\1/p')"
  [ -n "$name" ] || return 1
  adb -s "$DEV" shell "$CLIENT --name $name --exec 'id -u'" 2>/dev/null | tr -d '\r' | grep -qx 0
}

selinux() {
  adb -s "$DEV" shell getenforce 2>/dev/null | tr -d '\r'
}

if [ "${1:-}" = "--status" ]; then
  state
  if root_uid; then echo "root=SI"; else echo "root=NO"; fi
  exit 0
fi

if [ "${1:-}" = "--attempts" ]; then
  MAX_ATTEMPTS="${2:?falta el numero}"
fi

echo "[*] esperando arranque de $DEV"
b=""
for i in $(seq 1 60); do
  b="$(adb -s "$DEV" shell getprop sys.boot_completed 2>/dev/null | tr -d '\r')"
  [ "$b" = "1" ] && break
  sleep 3
done
[ "${b:-}" = "1" ] || die "el GS no ha arrancado"

if root_uid; then
  echo "[+] ya hay root vivo; no se lanza nada"
  exit 0
fi

[ "$(selinux)" = "Enforcing" ] || die "SELinux está en '$(selinux)': reinicia el GS antes de intentar"

[ -f "$BUNDLE" ] || die "falta $BUNDLE"
echo "[*] generando wrapper preserve-init"
sed -e 's/GHOST_SELINUX_PRESERVE_INIT=0/GHOST_SELINUX_PRESERVE_INIT=1/' \
    "$BUNDLE" > "$PATCHED" || die "no se pudo generar el wrapper"
grep -aq "GHOST_SELINUX_PRESERVE_INIT=1" "$PATCHED" || die "el parche no se aplicó"
echo "[*] wrapper: $(sha256sum "$PATCHED" | cut -d' ' -f1)"

adb -s "$DEV" push "$PATCHED" "$REMOTE" >/dev/null || die "push fallido"
adb -s "$DEV" shell "chmod 755 $REMOTE" >/dev/null 2>&1

attempt=1
while [ "$attempt" -le "$MAX_ATTEMPTS" ]; do
  echo
  echo "[*] intento $attempt/$MAX_ATTEMPTS (perf-loops=$PERF_LOOPS settle-us=$SETTLE_US)"
  adb -s "$DEV" shell 'am kill-all; svc power stayon true' >/dev/null 2>&1

  timeout "$RUN_TIMEOUT" adb -s "$DEV" shell \
    "sh $REMOTE --perf-loops $PERF_LOOPS --settle-us $SETTLE_US --exec 'id; getenforce'" \
    >> "$LOG" 2>&1
  grep -aE "W1 |W2 |ROOT AGENT|uid=0|failed|REJECTED" "$LOG" | tail -6

  if root_uid; then
    echo "[+] root OK en el intento $attempt"
    sleep 5
    state
    echo "[+] agente en $READY; reengancha con: ./attach.sh 'id -u'"
    exit 0
  fi

  sel="$(selinux)"
  if [ "$sel" != "Enforcing" ]; then
    echo "[!] SELinux ha quedado en '$sel' sin agente: estado no fiable."
    echo "    Reinicia el GS antes de volver a intentarlo (un intento por arranque)."
    state
    exit 2
  fi

  echo "[-] intento $attempt sin root; SELinux sigue Enforcing (no se escribió nada)"
  attempt=$((attempt + 1))
  [ "$attempt" -le "$MAX_ATTEMPTS" ] && sleep "$ATTEMPT_PAUSE"
done

echo "[!] agotados $MAX_ATTEMPTS intentos sin root. El GS sigue usable; log: $LOG"
state
exit 1
