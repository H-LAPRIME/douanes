#!/usr/bin/env bash
# douanes.sh - Orchestrateur principal du projet Douanes
# Tache : T4 | Responsable : H-LAPRIME
# Depend de : lib/interfaces.sh, lib/roles.sh, lib/admin_handler.sh, lib/llm_advisor.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIB_DIR="$SCRIPT_DIR/lib"

source_if_exists() {
    local file="$1"
    if [[ -f "$file" ]]; then
        # shellcheck source=/dev/null
        source "$file"
    fi
}

source "$LIB_DIR/interfaces.sh"

# Modules des autres taches : charges automatiquement quand ils existent.
source_if_exists "$LIB_DIR/logger_config.sh"
source_if_exists "$LIB_DIR/logger.sh"
source_if_exists "$LIB_DIR/log_rotation.sh"
source_if_exists "$LIB_DIR/check_lists.sh"
source_if_exists "$LIB_DIR/regex_patterns.sh"
source_if_exists "$LIB_DIR/scoring.sh"
source_if_exists "$LIB_DIR/analyze_command.sh"
source_if_exists "$LIB_DIR/subshell_exec.sh"
source_if_exists "$LIB_DIR/timeout_watcher.sh"
source_if_exists "$LIB_DIR/execute_secure.sh"

source "$LIB_DIR/roles.sh"
source "$LIB_DIR/admin_handler.sh"
source "$LIB_DIR/llm_advisor.sh"

if [[ $# -eq 0 ]]; then
    echo "Usage: $0 <commande>"
    exit 1
fi

CMD="$*"
USER_ROLE="$(get_user_role "$(get_current_user)")"

log_event "INFO" "$CMD" 0 "Commande soumise par $(get_current_user)"

ANALYSIS="$(analyze_command "$CMD")"
REST="${ANALYSIS#*|}"
SCORE="${REST%%|*}"

maybe_consult_llm "$CMD" "$SCORE" || true

execute_secure "$CMD" "$USER_ROLE"
