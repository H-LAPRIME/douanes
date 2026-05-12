#!/usr/bin/env bash
# roles.sh - Gestion des roles utilisateur/administrateur
# Tache : T4 | Responsable : H-LAPRIME
# Depend de : interfaces.sh

set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

source "$SCRIPT_DIR/interfaces.sh"

DOUANES_CONF_DIR="${DOUANES_CONF_DIR:-$PROJECT_DIR/conf}"
USERS_FILE="${USERS_FILE:-$DOUANES_CONF_DIR/users.conf}"

get_current_user() {
    if [[ -n "${DOUANES_TEST_USER:-}" ]]; then
        echo "$DOUANES_TEST_USER"
    elif command -v whoami >/dev/null 2>&1; then
        whoami
    else
        echo "${USER:-unknown}"
    fi
}

normalize_role() {
    local role="${1:-user}"
    case "$role" in
        admin|user) echo "$role" ;;
        *) echo "user" ;;
    esac
}

# Retourne le role de l'utilisateur : admin ou user.
get_user_role() {
    local username="$1"
    local uname
    local role

    if [[ -z "$username" || ! -f "$USERS_FILE" ]]; then
        echo "user"
        return 0
    fi

    while IFS=: read -r uname role _; do
        [[ -z "${uname:-}" || "$uname" == \#* ]] && continue
        if [[ "$uname" == "$username" ]]; then
            normalize_role "$role"
            return 0
        fi
    done < "$USERS_FILE"

    echo "user"
}

# Retourne 0 si l'utilisateur courant est admin, 1 sinon.
is_admin() {
    local username
    local role

    username="$(get_current_user)"
    role="$(get_user_role "$username")"
    [[ "$role" == "admin" ]]
}

# Double confirmation admin pour les actions sensibles.
require_admin_confirmation() {
    local action="$1"
    local username
    local confirm1
    local confirm2

    username="$(get_current_user)"

    if ! is_admin; then
        echo "[ERROR] Acces refuse : droits administrateur requis."
        log_event "ERROR" "$action" 0 "Tentative admin refusee pour $username"
        return 1
    fi

    echo "[ADMIN-WARN] Action sensible : $action"
    read -r -p "Confirmer (tapez exactement 'oui') : " confirm1
    if [[ "$confirm1" != "oui" ]]; then
        echo "[INFO] Action annulee."
        log_audit "ADMIN_CONFIRM_CANCEL" "$username a annule : $action"
        return 1
    fi

    read -r -p "Confirmer a nouveau : " confirm2
    if [[ "$confirm2" != "oui" ]]; then
        echo "[INFO] Confirmation echouee. Action annulee."
        log_audit "ADMIN_CONFIRM_FAILED" "$username a echoue la double confirmation : $action"
        return 1
    fi

    log_audit "ADMIN_CONFIRM_OK" "$username a confirme : $action"
    return 0
}
