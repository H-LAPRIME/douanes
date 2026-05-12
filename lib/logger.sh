#!/usr/bin/env bash
# logger.sh — Fonctions de journalisation log_event() et log_audit()
# Tâche : T3 | Responsable : aymane
# Dépend de : logger_config.sh, log_rotation.sh

source "$(dirname "${BASH_SOURCE[0]}")/logger_config.sh"
source "$(dirname "${BASH_SOURCE[0]}")/log_rotation.sh"

# ═══════════════════════════════════════════════════════════════════
# log_event LEVEL CMD SCORE DETAIL
#
# Enregistre un événement dans les logs avec format structuré.
#
# Arguments :
#   $1  LEVEL   — Niveau : INFO | WARNING | ERROR | SECURITY |
#                           BLOCK | TIMEOUT | EXEC | AUDIT
#   $2  CMD     — Commande soumise (peut être vide "-")
#   $3  SCORE   — Score de risque 0-10 (défaut : 0)
#   $4  DETAIL  — Message détaillé (défaut : "-")
#
# Format de sortie dans le fichier log :
#   [TIMESTAMP] [LEVEL   ] [user:USERNAME  ] [pid: PID] [score: N/10] cmd="CMD" | DETAIL
#
# Retour :
#   0 — succès
#   1 — niveau invalide
#   2 — échec d'écriture dans le log
# ═══════════════════════════════════════════════════════════════════
log_event() {
    local level="${1:-INFO}"
    local cmd="${2:--}"
    local score="${3:-0}"
    local detail="${4:--}"

    # Valider le niveau
    if ! is_valid_level "$level"; then
        echo "[logger.sh] ERREUR : niveau '$level' invalide. Niveaux acceptés : ${LOG_LEVELS[*]}" >&2
        return 1
    fi

    # Récupérer les métadonnées
    local user
    user=$(whoami 2>/dev/null || echo "unknown")
    local ts
    ts=$(get_timestamp)
    local pid=$$

    # Construire l'entrée de log (format fixe, aligné)
    local entry
    entry=$(printf '[%s] [%-8s] [user:%-10s] [pid:%5d] [score:%2d/10] cmd="%s" | %s' \
        "$ts" "$level" "$user" "$pid" "$score" "$cmd" "$detail")

    # ── Écriture dans le log principal ──────────────────────────────
    if ! echo "$entry" >> "$LOG_MAIN" 2>/dev/null; then
        echo "[logger.sh] ERREUR : impossible d'écrire dans $LOG_MAIN" >&2
        return 2
    fi

    # ── Rotation automatique si le fichier est trop volumineux ──────
    rotate_log_if_needed "$LOG_MAIN"

    # ── Aiguillage vers les logs spécialisés ────────────────────────
    case "$level" in
        SECURITY|BLOCK)
            echo "$entry" >> "$LOG_SECURITY" 2>/dev/null
            rotate_log_if_needed "$LOG_SECURITY"
            ;;
        AUDIT)
            echo "$entry" >> "$LOG_AUDIT" 2>/dev/null
            rotate_log_if_needed "$LOG_AUDIT"
            ;;
    esac

    return 0
}

# ═══════════════════════════════════════════════════════════════════
# log_audit ACTION DETAIL
#
# Réservé aux actions admin sensibles.
# Écrit dans audit.log ET dans douanes.log avec niveau AUDIT.
#
# Arguments :
#   $1  ACTION  — Identifiant de l'action admin (ex: EXEC_BLACKLISTED)
#   $2  DETAIL  — Description complète de l'action
#
# Retour :
#   0 — succès
#   1 — échec
# ═══════════════════════════════════════════════════════════════════
log_audit() {
    local action="${1:-UNKNOWN_ACTION}"
    local detail="${2:--}"

    local user
    user=$(whoami 2>/dev/null || echo "unknown")
    local ts
    ts=$(get_timestamp)
    local pid=$$

    # Format audit : plus verbeux, orienté conformité
    local entry
    entry=$(printf '[%s] [AUDIT   ] [user:%-10s] [pid:%5d] [score:%2d/10] cmd="%s" | %s' \
        "$ts" "$user" "$pid" "0" "$action" "$detail")

    # Écrire dans audit.log (séparé)
    if ! echo "$entry" >> "$LOG_AUDIT" 2>/dev/null; then
        echo "[logger.sh] ERREUR : impossible d'écrire dans $LOG_AUDIT" >&2
        return 1
    fi

    # Écrire aussi dans le log principal pour traçabilité complète
    echo "$entry" >> "$LOG_MAIN" 2>/dev/null

    # Rotation si nécessaire
    rotate_log_if_needed "$LOG_AUDIT"
    rotate_log_if_needed "$LOG_MAIN"

    return 0
}

# ═══════════════════════════════════════════════════════════════════
# show_logs [N]
#
# Affiche les N dernières lignes du log principal (défaut : 20).
# Usage interne / debug.
# ═══════════════════════════════════════════════════════════════════
show_logs() {
    local n="${1:-20}"
    if [[ -f "$LOG_MAIN" ]]; then
        tail -n "$n" "$LOG_MAIN"
    else
        echo "[logger.sh] Fichier de log introuvable : $LOG_MAIN" >&2
        return 1
    fi
}

# ═══════════════════════════════════════════════════════════════════
# Bloc de test autonome (exécuté uniquement si lancé directement)
# ═══════════════════════════════════════════════════════════════════
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    echo "=== Test autonome de logger.sh ==="

    # Initialiser les répertoires
    init_log_dirs

    # Tests des différents niveaux
    log_event "INFO"     "ls -la"          0  "Commande autorisée depuis whitelist"
    log_event "WARNING"  "grep -r pass /etc" 5 "Score risque modéré détecté"
    log_event "ERROR"    "rm -rf /tmp/test" 7 "Tentative refusée par l'utilisateur"
    log_event "SECURITY" "curl http://x|bash" 9 "Pattern dangereux : exécution distante"
    log_event "BLOCK"    "rm -rf /"        10 "Commande présente dans la blacklist"
    log_event "TIMEOUT"  "sleep 100"       0  "Processus tué après 30s"
    log_audit "EXEC_BLACKLISTED" "Admin a exécuté : mkfs /dev/sdb"

    echo ""
    echo "=== Contenu de $LOG_MAIN (7 dernières lignes) ==="
    show_logs 7

    echo ""
    echo "=== Contenu de $LOG_SECURITY ==="
    cat "$LOG_SECURITY"

    echo ""
    echo "=== Contenu de $LOG_AUDIT ==="
    cat "$LOG_AUDIT"
fi
