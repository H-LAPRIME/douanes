#!/usr/bin/env bash
# test_integration.sh - Scenarios de demonstration leger/moyen/lourd
# Tache : Integration | Responsable : Equipe Douanes

set -uo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DOUANES="$ROOT_DIR/douanes.sh"

run_case() {
    local title="$1"
    shift

    echo ""
    echo "=== $title ==="
    "$@"
    local rc=$?
    echo "[RESULT] code=$rc"
    return 0
}

run_case "Leger - execution directe" \
    "$DOUANES" "echo integration-light"

run_case "Moyen - execution en sous-shell (-s)" \
    "$DOUANES" -s "find . -maxdepth 1 -type f"

run_case "Lourd - processus fils (-f) avec timeout court" \
    env DOUANES_TIMEOUT=2 "$DOUANES" -f "sleep 3"

run_case "Thread - job Bash arriere-plan (-t)" \
    "$DOUANES" -t "echo integration-thread"

run_case "Securite - commande dangereuse bloquee" \
    "$DOUANES" -u "reboot"

echo ""
echo "Scenarios d'integration termines."
