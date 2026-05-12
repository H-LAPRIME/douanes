#!/usr/bin/env bash
# test_t4.sh - Tests unitaires Tache 4
# Tache : T4 | Responsable : H-LAPRIME
# Depend de : lib/roles.sh, lib/admin_handler.sh, lib/llm_advisor.sh

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP_DIR="$(mktemp -d)"

export DOUANES_CONF_DIR="$TMP_DIR/conf"
export DOUANES_LOG_DIR="$TMP_DIR/logs"
export USERS_FILE="$DOUANES_CONF_DIR/users.conf"

mkdir -p "$DOUANES_CONF_DIR" "$DOUANES_LOG_DIR"
cat > "$USERS_FILE" <<EOF
admin1:admin:x
user1:user:x
EOF

source "$ROOT_DIR/lib/roles.sh"
source "$ROOT_DIR/lib/admin_handler.sh"
source "$ROOT_DIR/lib/llm_advisor.sh"

assert_equals() {
    local expected="$1"
    local actual="$2"
    local message="$3"

    if [[ "$expected" != "$actual" ]]; then
        echo "[FAIL] $message"
        echo "       attendu : $expected"
        echo "       obtenu  : $actual"
        exit 1
    fi
    echo "[OK] $message"
}

assert_success() {
    local message="$1"
    shift

    if "$@"; then
        echo "[OK] $message"
    else
        echo "[FAIL] $message"
        exit 1
    fi
}

assert_failure() {
    local message="$1"
    shift

    if "$@"; then
        echo "[FAIL] $message"
        exit 1
    else
        echo "[OK] $message"
    fi
}

assert_equals "admin" "$(get_user_role "admin1")" "get_user_role retourne admin"
assert_equals "user" "$(get_user_role "user1")" "get_user_role retourne user"
assert_equals "user" "$(get_user_role "inconnu")" "role par defaut user"

export DOUANES_TEST_USER="user1"
assert_failure "is_admin refuse un utilisateur standard" is_admin
assert_failure "admin_reset_logs refuse un utilisateur standard" admin_reset_logs

export DOUANES_TEST_USER="admin1"
assert_success "is_admin accepte un administrateur" is_admin
printf 'oui\noui\n' | admin_modify_rules "blacklist" "rm -rf /" "add" >/tmp/douanes_t4_rule.out
assert_success "admin_modify_rules ajoute une regle" grep -Fxq "rm -rf /" "$DOUANES_CONF_DIR/blacklist.conf"

assert_success "maybe_consult_llm ignore les scores bas sans erreur" maybe_consult_llm "ls -la" 1

echo "[OK] Tests T4 termines"
