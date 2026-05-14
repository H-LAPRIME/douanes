#!/usr/bin/env bash
# douanes.sh - Orchestrateur principal du projet Douanes
# Tache : T4 | Responsable : H-LAPRIME
# Depend de : lib/interfaces.sh, lib/roles.sh, lib/admin_handler.sh, lib/llm_advisor.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# Revenir au dossier d'origine utilisateur
if [[ -n "${PWD_ORIG:-}" ]]; then
    cd "$PWD_ORIG" || {
        echo "[ERROR] Impossible d'acceder au repertoire utilisateur : $PWD_ORIG"
        exit 1
    }
fi
LIB_DIR="$SCRIPT_DIR/lib"
PROGRAM_NAME="douanes"
THREAD_SRC="$LIB_DIR/thread_handler.c"
THREAD_BIN="${DOUANES_THREAD_BIN:-$LIB_DIR/thread_handler}"

ERR_UNKNOWN_OPTION=100
ERR_MISSING_PARAMETER=101
ERR_PROCESSING_FAILED=102
ERR_ADMIN_REQUIRED=103

EXEC_MODE="direct"
RESTORE_DEFAULTS=0
CUSTOM_LOG_DIR=""
FORCE_ROLE=""
INTERNAL_THREAD_WORKER=0
THREAD_WORKER_ROLE=""
THREAD_WORKER_CMD=""

print_help() {
    cat <<'EOF'
Douanes - Intermediaire securise pour commandes Linux

Syntaxe:
  douanes [options] "commande"

Options:
  -h              Affiche cette aide detaillee.
  -s              Execute le traitement Douanes dans un sous-shell.
  -f              Execute le traitement par creation d'un processus fils.
  -t              Execute le traitement via un vrai thread C pthread.
  -l <repertoire> Definit le repertoire des logs et du fichier history.log.
  -r              Restaure/reinitialise les logs par defaut. Admin uniquement.
  -a              Force l'execution en role admin. Necessite un utilisateur admin.
  -u              Force l'execution en role user, meme si l'utilisateur est admin.

Parametre obligatoire:
  commande        Commande Unix/Linux a analyser puis executer si elle est autorisee.

Role d'execution:
  Le role est detecte automatiquement depuis conf/users.conf.
  Exemple admin: username:admin:test
  Le programme affiche "Execution en tant que admin" ou "Execution en tant que user".

Codes d'erreur:
  100  Option inexistante.
  101  Parametre obligatoire manquant.
  102  Echec de traitement ou d'execution.
  103  Privileges administrateur requis.

Exemples:
  douanes -h
  douanes "ls -la"
  douanes -s "echo hello"
  douanes -f "find . -maxdepth 2 -type f"
  douanes -t "grep -R TODO lib"
  douanes -l logs-demo "pwd"
  douanes -r
  douanes -a "reboot"
  douanes -u "reboot"

Journalisation:
  Les sorties stdout/stderr sont affichees au terminal et copiees dans history.log.
  Format history.log:
  yyyy-mm-dd-hh-mm-ss : username : INFOS : message
  yyyy-mm-dd-hh-mm-ss : username : ERROR : message
EOF
}

die_with_help() {
    local code="$1"
    local message="$2"
    echo "[ERROR] $message" >&2
    print_help >&2
    exit "$code"
}

default_log_dir() {

    # Linux avec accès root
    if [[ -d /var/log && -w /var/log ]]; then
        echo "/var/log/$PROGRAM_NAME"
        return
    fi

    # Git Bash / utilisateur normal
    mkdir -p "$HOME/.douanes" 2>/dev/null || true
    echo "$HOME/.douanes/logs"
}

init_history_logging() {
    local log_dir="$1"
    local history_file
    local user

    if ! mkdir -p "$log_dir" 2>/dev/null; then
        log_dir="logs"
        mkdir -p "$log_dir"
    fi

    history_file="$log_dir/history.log"
    touch "$history_file"
    user="$(whoami 2>/dev/null || echo unknown)"

    export DOUANES_HISTORY_FILE="$history_file"
    export DOUANES_HISTORY_USER="$user"

    exec > >(while IFS= read -r line; do
        printf '%s\n' "$line"
        printf '%s : %s : INFOS : %s\n' "$(date '+%Y-%m-%d-%H-%M-%S')" "$DOUANES_HISTORY_USER" "$line" >> "$DOUANES_HISTORY_FILE"
    done)

    exec 2> >(while IFS= read -r line; do
        printf '%s\n' "$line" >&2
        printf '%s : %s : ERROR : %s\n' "$(date '+%Y-%m-%d-%H-%M-%S')" "$DOUANES_HISTORY_USER" "$line" >> "$DOUANES_HISTORY_FILE"
    done)
}

source_if_exists() {
    local file="$1"
    if [[ -f "$file" ]]; then
        # shellcheck source=/dev/null
        source "$file"
    fi
}

shell_quote() {
    local value="$1"
    printf "'%s'" "${value//\'/\'\\\'\'}"
}

thread_runner_path() {
    if [[ -x "$THREAD_BIN" ]]; then
        printf '%s\n' "$THREAD_BIN"
        return 0
    fi

    if [[ -x "$THREAD_BIN.exe" ]]; then
        printf '%s\n' "$THREAD_BIN.exe"
        return 0
    fi

    return 1
}

ensure_thread_runner() {
    local runner

    if [[ ! -f "$THREAD_SRC" ]]; then
        return 1
    fi

    if runner="$(thread_runner_path)" && [[ "$runner" -nt "$THREAD_SRC" ]]; then
        THREAD_BIN="$runner"
        return 0
    fi

    if ! command -v gcc >/dev/null 2>&1; then
        return 1
    fi

    if ! gcc -Wall -Wextra -O2 -pthread "$THREAD_SRC" -o "$THREAD_BIN" 2>/dev/null; then
        return 1
    fi

    if runner="$(thread_runner_path)"; then
        THREAD_BIN="$runner"
        return 0
    fi

    return 1
}

if [[ "${1:-}" == "--thread-worker" ]]; then
    if [[ $# -lt 3 ]]; then
        die_with_help "$ERR_MISSING_PARAMETER" "Worker thread incomplet : role et commande requis."
    fi
    INTERNAL_THREAD_WORKER=1
    THREAD_WORKER_ROLE="$2"
    THREAD_WORKER_CMD="$3"
    shift 3
fi

if (( INTERNAL_THREAD_WORKER == 0 )); then
    while getopts ":hfstl:rau" opt; do
        case "$opt" in
            h)
                print_help
                exit 0
                ;;
            f)
                EXEC_MODE="fork"
                ;;
            s)
                EXEC_MODE="subshell"
                ;;
            t)
                EXEC_MODE="thread"
                ;;
            l)
                CUSTOM_LOG_DIR="$OPTARG"
                ;;
            r)
                RESTORE_DEFAULTS=1
                ;;
            a)
                FORCE_ROLE="admin"
                ;;
            u)
                FORCE_ROLE="user"
                ;;
            :)
                die_with_help "$ERR_MISSING_PARAMETER" "Option -$OPTARG requiert un parametre."
                ;;
            \?)
                die_with_help "$ERR_UNKNOWN_OPTION" "Option inconnue : -$OPTARG"
                ;;
        esac
    done
    shift $((OPTIND - 1))
fi

LOG_DIR="${CUSTOM_LOG_DIR:-$(default_log_dir)}"
export DOUANES_LOG_DIR="$LOG_DIR"

init_history_logging "$LOG_DIR"

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

if (( RESTORE_DEFAULTS == 1 )); then
    if ! is_admin; then
        die_with_help "$ERR_ADMIN_REQUIRED" "L'option -r est reservee aux administrateurs."
    fi
    admin_reset_logs || exit "$ERR_PROCESSING_FAILED"
    exit 0
fi

if (( INTERNAL_THREAD_WORKER == 1 )); then
    CMD="$THREAD_WORKER_CMD"
    USER_ROLE="$THREAD_WORKER_ROLE"
else
    if [[ $# -lt 1 ]]; then
        die_with_help "$ERR_MISSING_PARAMETER" "Parametre obligatoire manquant : commande a analyser."
    fi

    CMD="$*"
    USER_ROLE="$(get_user_role "$(get_current_user)")"
fi

case "$FORCE_ROLE" in
    admin)
        if ! is_admin; then
            die_with_help "$ERR_ADMIN_REQUIRED" "L'option -a necessite un utilisateur admin dans conf/users.conf."
        fi
        USER_ROLE="admin"
        ;;
    user)
        USER_ROLE="user"
        ;;
esac

if (( INTERNAL_THREAD_WORKER == 0 )); then
    echo "[ROLE] Execution en tant que $USER_ROLE"
fi

run_security_flow() {
    local cmd="$1"
    local role="$2"
    local analysis decision rest score reasons rc

    log_event "INFO" "$cmd" 0 "Commande soumise par $(get_current_user)"

    analysis="$(analyze_command "$cmd" "$role")"
    decision="${analysis%%|*}"
    rest="${analysis#*|}"
    score="${rest%%|*}"
    reasons="${rest#*|}"

    echo "[ANALYSE] Decision : $decision | Score : $score/10"
    echo "[ANALYSE] Justification : $reasons"

    maybe_consult_llm "$cmd" "$score" "$decision" "$reasons" || true

    set +e
    execute_secure "$cmd" "$role"
    rc=$?
    set -e
    return "$rc"
}

if (( INTERNAL_THREAD_WORKER == 1 )); then
    run_security_flow "$CMD" "$USER_ROLE"
    exit $?
fi

case "$EXEC_MODE" in
    direct)
        run_security_flow "$CMD" "$USER_ROLE"
        ;;
    subshell)
        echo "[MODE] subshell"
        ( run_security_flow "$CMD" "$USER_ROLE" )
        ;;
    fork)
        echo "[MODE] fork - processus fils"
        ( run_security_flow "$CMD" "$USER_ROLE" ) &
        child_pid=$!
        wait "$child_pid"
        ;;
    thread)
        if ensure_thread_runner; then
            worker_cmd="cd $(shell_quote "$SCRIPT_DIR") && ./douanes.sh --thread-worker $(shell_quote "$USER_ROLE") $(shell_quote "$CMD")"
            echo "[MODE] thread - pthread C"
            "$THREAD_BIN" bash -lc "$worker_cmd"
        else
            echo "[MODE] thread - fallback job Bash"
            ( run_security_flow "$CMD" "$USER_ROLE" ) &
            thread_pid=$!
            wait "$thread_pid"
        fi
        ;;
    *)
        die_with_help "$ERR_UNKNOWN_OPTION" "Mode d'execution invalide : $EXEC_MODE"
        ;;
esac
