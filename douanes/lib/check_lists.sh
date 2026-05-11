#!/usr/bin/env bash
# =============================================================================
# check_lists.sh — Vérification Whitelist / Blacklist
# Tâche : T1 | Responsable : Doha
# Dépend de : /etc/douanes/whitelist.conf, blacklist.conf
# Projet : douanes 
# Usage   : source check_lists.sh
# =============================================================================

WHITELIST="/etc/douanes/whitelist.conf"
BLACKLIST="/etc/douanes/blacklist.conf"

is_whitelisted() {
    local cmd="$1"

    # Extraire le premier mot = la commande de base
    local base_cmd
    base_cmd=$(echo "$cmd" | awk '{print $1}')

    # Vérifier que le fichier whitelist existe
    if [[ ! -f "$WHITELIST" ]]; then
        echo -e "\033[0;31m[ERROR]\033[0m Whitelist introuvable : $WHITELIST" >&2
        return 1
    fi

    # Parcourir la whitelist ligne par ligne
    while IFS= read -r line; do
        # Ignorer les lignes vides et les commentaires
        [[ -z "$line" || "$line" == \#* ]] && continue

        # Comparer la commande de base avec chaque entrée
        if [[ "$base_cmd" == "$line" ]]; then
            return 0  # Trouvé dans la whitelist
        fi
    done < "$WHITELIST"

    return 1  # Pas dans la whitelist
}

# =============================================================================
# is_blacklisted CMD
# Vérifie si la commande contient un pattern de la blacklist
# Utilise une correspondance partielle (pattern inclus dans la commande)
# Retourne : 0 (trouvé = dangereux) | 1 (non trouvé = ok)
# =============================================================================
is_blacklisted() {
    local cmd="$1"

    # Vérifier que le fichier blacklist existe
    if [[ ! -f "$BLACKLIST" ]]; then
        echo -e "\033[0;31m[ERROR]\033[0m Blacklist introuvable : $BLACKLIST" >&2
        return 1
    fi

    # Parcourir la blacklist ligne par ligne
    while IFS= read -r line; do
        # Ignorer les lignes vides et les commentaires
        [[ -z "$line" || "$line" == \#* ]] && continue

        # Correspondance partielle : le pattern est-il contenu dans la commande ?
        if echo "$cmd" | grep -qE "$line"; then
            return 0  # Pattern blacklisté trouvé dans la commande
        fi
    done < "$BLACKLIST"

    return 1  # Aucun pattern blacklisté trouvé
}

# =============================================================================
# get_blacklist_match CMD
# Retourne le pattern blacklist qui correspond à la commande
# Utile pour afficher dans les logs pourquoi c'est bloqué
# =============================================================================
get_blacklist_match() {
    local cmd="$1"

    if [[ ! -f "$BLACKLIST" ]]; then
        echo "blacklist introuvable"
        return 1
    fi

    while IFS= read -r line; do
        [[ -z "$line" || "$line" == \#* ]] && continue

        if echo "$cmd" | grep -qE "$line"; then
            echo "$line"  # Retourner le pattern qui a matché
            return 0
        fi
    done < "$BLACKLIST"

    echo ""
    return 1
}

# =============================================================================
# check_lists_status
# Affiche l'état des fichiers de règles (existe / manquant / nb entrées)
# =============================================================================
check_lists_status() {
    echo "=== Statut des fichiers de règles ==="

    for file_label in "Whitelist:$WHITELIST" "Blacklist:$BLACKLIST"; do
        local label="${file_label%%:*}"
        local path="${file_label##*:}"

        if [[ -f "$path" ]]; then
            local count
            count=$(grep -cv '^\s*#\|^\s*$' "$path" 2>/dev/null || echo 0)
            echo -e "  \033[0;32m[OK]\033[0m $label : $path ($count entrées actives)"
        else
            echo -e "  \033[0;31m[MANQUANT]\033[0m $label : $path"
        fi
    done
    echo "======================================"
}

# =============================================================================
# TEST AUTONOME — si le script est exécuté directement (pas sourcé)
# =============================================================================
if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    echo "=== Test de check_lists.sh ==="
    check_lists_status
    echo ""

    test_cmds=("ls" "ls -la" "rm -rf /" "sudo su" "grep motif fichier" "shutdown now")

    for cmd in "${test_cmds[@]}"; do
        if is_blacklisted "$cmd"; then
            match=$(get_blacklist_match "$cmd")
            printf "  %-30s => \033[0;31mBLACKLIST\033[0m (pattern: '%s')\n" "$cmd" "$match"
        elif is_whitelisted "$cmd"; then
            printf "  %-30s => \033[0;32mWHITELIST\033[0m\n" "$cmd"
        else
            printf "  %-30s => \033[1;33mNEUTRE\033[0m (scoring nécessaire)\n" "$cmd"
        fi
    done
fi

