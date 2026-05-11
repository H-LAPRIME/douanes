#!/usr/bin/env bash
# timeout_watcher.sh — Surveillance et kill par timeout
# Tâche : T2 | Responsable : khalid
# Dépend de : lib/interfaces.sh (log_event)

# Timeout par défaut en secondes (surchargeable via variable d'environnement)
DOUANES_TIMEOUT="${DOUANES_TIMEOUT:-30}"

# =============================================================================
# watch_process CMD [TIMEOUT]
#
#   Lance CMD en arrière-plan et la surveille.
#   Si elle dépasse TIMEOUT secondes : SIGTERM → 2s → SIGKILL.
#
#   Paramètres :
#     $1  cmd     — Commande à exécuter (chaîne)
#     $2  timeout — (optionnel) Timeout en secondes, défaut $DOUANES_TIMEOUT
#
#   Retour :
#     0   — Commande terminée normalement
#     255 — Timeout (convention bash pour -1)
#     N   — Code de sortie de la commande
#
#   Stdout/stderr de la commande sont capturés dans les fichiers
#   $STDOUT_FILE / $STDERR_FILE (initialisés par init_tmpdir).
#
#   Détection du timeout : par code de signal (SIGTERM=143, SIGKILL=137),
#   plus fiable que l'écriture d'un marqueur fichier (pas de race condition).
# =============================================================================
watch_process() {
    local cmd="${1:?watch_process: commande requise}"
    local timeout="${2:-$DOUANES_TIMEOUT}"
    local cmd_pid
    local watcher_pid
    local cmd_rc=0

    # ── Lancer la commande dans le sous-shell isolé ───────────────────────
    run_in_subshell "$cmd" > /dev/null
    cmd_pid=$(cat "$PID_FILE")

    # ── Lancer le watchdog en arrière-plan ────────────────────────────────
    # Le watchdog dort TIMEOUT secondes puis tue le processus s'il vit encore.
    (
        sleep "$timeout"
        if kill -0 "$cmd_pid" 2>/dev/null; then
            kill -TERM "$cmd_pid" 2>/dev/null
            sleep 2
            kill -0 "$cmd_pid" 2>/dev/null && kill -KILL "$cmd_pid" 2>/dev/null
        fi
    ) &
    watcher_pid=$!

    # ── Attendre la fin de la commande ────────────────────────────────────
    wait "$cmd_pid" 2>/dev/null
    cmd_rc=$?

    # ── Arrêter le watchdog s'il tourne encore (fin naturelle) ────────────
    if kill -0 "$watcher_pid" 2>/dev/null; then
        kill "$watcher_pid" 2>/dev/null
        wait "$watcher_pid" 2>/dev/null || true
    fi

    # ── Détecter le timeout par code de signal ────────────────────────────
    # SIGTERM → code 143  |  SIGKILL → code 137
    if [[ "$cmd_rc" -eq 143 ]] || [[ "$cmd_rc" -eq 137 ]]; then
        log_event "TIMEOUT" "$cmd" 0 "Commande tuée après ${timeout}s (rc=$cmd_rc)"
        return 255   # Convention bash pour -1 (timeout)
    fi

    return "$cmd_rc"
}

# =============================================================================
# get_return_code RC
#
#   Interprète un code de retour numérique et retourne un label lisible.
#   Utilisé pour les messages de log dans execute_secure.
#
#   Paramètres :
#     $1  rc — Code de retour numérique
#
#   Sortie stdout : label descriptif
# =============================================================================
get_return_code() {
    local rc="${1:?get_return_code: code requis}"
    case "$rc" in
        0)   echo "SUCCESS"              ;;
        1)   echo "ERROR_GENERAL"        ;;
        2)   echo "ERROR_SECURITY"       ;;
        126) echo "ERROR_NOT_EXECUTABLE" ;;
        127) echo "ERROR_NOT_FOUND"      ;;
        130) echo "INTERRUPTED_SIGINT"   ;;
        137) echo "KILLED_SIGKILL"       ;;
        143) echo "KILLED_SIGTERM"       ;;
        255) echo "TIMEOUT"              ;;
        *)   echo "ERROR_UNKNOWN_$rc"    ;;
    esac
}
