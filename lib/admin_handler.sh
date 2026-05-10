#!/usr/bin/env bash
# admin_handler.sh - Gestion des cas administrateur A1-A5
# Tache : T4 | Responsable : H-LAPRIME
# Depend de : roles.sh, interfaces.sh

set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

source "$SCRIPT_DIR/roles.sh"

DOUANES_CONF_DIR="${DOUANES_CONF_DIR:-$PROJECT_DIR/conf}"
DOUANES_LOG_DIR="${DOUANES_LOG_DIR:-$PROJECT_DIR/logs}"

get_rule_file() {
    local rule_type="$1"

    case "$rule_type" in
        whitelist) echo "$DOUANES_CONF_DIR/whitelist.conf" ;;
        blacklist) echo "$DOUANES_CONF_DIR/blacklist.conf" ;;
        users) echo "$DOUANES_CONF_DIR/users.conf" ;;
        *)
            echo ""
            return 1
            ;;
    esac
}

# A2/A3 : execution admin d'une commande bloquee, avec audit.
execute_blacklisted_as_admin() {
    local cmd="$1"
    local retcode

    echo "[ADMIN-WARN] Commande blacklistee : $cmd"
    echo "[ADMIN-WARN] Cette operation sera tracee dans les logs d'audit."

    if ! require_admin_confirmation "Execution commande blacklistee : $cmd"; then
        log_event "ERROR" "$cmd" 10 "Execution admin annulee/refusee"
        return 1
    fi

    log_audit "EXEC_BLACKLISTED" "$cmd"
    run_in_subshell "$cmd"
    retcode=$?

    log_event "AUDIT" "$cmd" 10 "Admin - Code retour: $retcode"
    return "$retcode"
}

# A4 : reinitialisation des logs, avec archivage avant vidage.
admin_reset_logs() {
    local logfile

    echo "[WARN] Reinitialisation des logs demandee."
    echo "[WARN] Une archive sera creee automatiquement."

    if ! require_admin_confirmation "Reinitialisation des logs"; then
        return 1
    fi

    archive_logs || {
        log_event "ERROR" "admin_reset_logs" 0 "Archivage impossible"
        echo "[ERROR] Archivage impossible. Reinitialisation annulee."
        return 1
    }

    mkdir -p "$DOUANES_LOG_DIR"
    for logfile in douanes.log audit.log security.log; do
        : > "$DOUANES_LOG_DIR/$logfile"
    done

    log_audit "RESET_LOGS" "Logs reinitialises et archives"
    echo "[INFO] Logs reinitialises."
}

# A5 : modification controlee des listes de securite.
admin_modify_rules() {
    local rule_type="$1"
    local new_rule="$2"
    local action="${3:-add}"
    local rule_file
    local backup_file
    local escaped_rule

    rule_file="$(get_rule_file "$rule_type")" || {
        echo "[ERROR] Type de regle invalide : $rule_type"
        log_event "ERROR" "admin_modify_rules" 0 "Type invalide: $rule_type"
        return 1
    }

    if [[ "$action" != "add" && "$action" != "remove" ]]; then
        echo "[ERROR] Action invalide : $action"
        log_event "ERROR" "admin_modify_rules" 0 "Action invalide: $action"
        return 1
    fi

    echo "[WARN] Modification des regles : $rule_type"
    echo "[WARN] Action : $action - Regle : $new_rule"

    if ! require_admin_confirmation "Modification regles $rule_type"; then
        return 1
    fi

    mkdir -p "$DOUANES_CONF_DIR"
    touch "$rule_file"
    backup_file="$rule_file.bak.$(date '+%Y%m%d_%H%M%S')"
    cp "$rule_file" "$backup_file"

    if [[ "$action" == "add" ]]; then
        if grep -Fxq "$new_rule" "$rule_file"; then
            echo "[INFO] Regle deja presente."
        else
            printf '%s\n' "$new_rule" >> "$rule_file"
            echo "[INFO] Regle ajoutee."
        fi
    else
        escaped_rule="$(printf '%s\n' "$new_rule" | sed 's/[\/&]/\\&/g')"
        sed -i "/^${escaped_rule}$/d" "$rule_file"
        echo "[INFO] Regle supprimee si elle existait."
    fi

    log_audit "MODIFY_RULES" "Type=$rule_type Action=$action Regle=$new_rule Backup=$backup_file"
    echo "[INFO] Backup disponible : $backup_file"
}
