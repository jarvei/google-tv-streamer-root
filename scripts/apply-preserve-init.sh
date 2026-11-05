#!/usr/bin/env bash
# apply-preserve-init.sh — one-line patch for the GhostLock kirkwood wrapper.
#
# The published wrapper forces GHOST_SELINUX_PRESERVE_INIT=0, which zeroes
# selinux_state.initialized and kills the framework. Setting it to 1 keeps
# SELinux Permissive with the policy loaded, so system_server survives.
#
# Usage:
#   ./apply-preserve-init.sh ghostlock-kirkwood-oneclick.sh [output]
set -euo pipefail

IN="${1:?usage: $0 <ghostlock-kirkwood-oneclick.sh> [output]}"
OUT="${2:-ghostlock-preserve.sh}"

[ -f "$IN" ] || { echo "not found: $IN" >&2; exit 1; }

# Sanity: the original bundle is a self-extracting shell script.
head -1 "$IN" | grep -q '^#!/system/bin/sh' || {
    echo "warning: $IN does not look like the kirwood one-click bundle" >&2
}

sed 's/GHOST_SELINUX_PRESERVE_INIT=0/GHOST_SELINUX_PRESERVE_INIT=1/' \
    "$IN" > "$OUT"

grep -q 'GHOST_SELINUX_PRESERVE_INIT=1' "$OUT" || {
    echo "patch did not apply (marker not found)" >&2
    exit 2
}

echo "patched: $OUT"
echo "push it and run one attempt per clean boot:"
echo "  adb push $OUT /data/local/tmp/"
echo "  adb shell 'sh /data/local/tmp/$(basename "$OUT") --perf-loops 60000 --settle-us 120000 --exec \"id; getenforce\"'"
