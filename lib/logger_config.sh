#!/usr/bin/env bash
# logger_config.sh — Configuration du système de journalisation
# Tâche : T3 | Responsable : aymane
# Dépend de : (aucune dépendance)

# ─────────────────────────────────────────────
# Répertoires et fichiers de logs
# ─────────────────────────────────────────────
LOG_DIR="/var/log/douanes"
LOG_MAIN="$LOG_DIR/douanes.log"
LOG_AUDIT="$LOG_DIR/audit.log"
LOG_SECURITY="$LOG_DIR/security.log"
LOG_ARCHIVE_DIR="$LOG_DIR/archives"

# ─────────────────────────────────────────────
# Paramètres de rotation
# ─────────────────────────────────────────────
# Taille maximale avant rotation : 5 Mo
LOG_MAX_SIZE=5242880

# Nombre maximum d'archives à conserver par fichier
LOG_MAX_ARCHIVES=10

# ─────────────────────────────────────────────
# Niveaux de log autorisés
# ─────────────────────────────────────────────
readonly LOG_LEVELS=("INFO" "WARNING" "ERROR" "SECURITY" "BLOCK" "AUDIT" "TIMEOUT" "EXEC")

# ─────────────────────────────────────────────
# Horodatage ISO 8601
# ─────────────────────────────────────────────
get_timestamp() {
    date '+%Y-%m-%dT%H:%M:%S%z'
}

# ─────────────────────────────────────────────
# Initialisation des répertoires et permissions
# ─────────────────────────────────────────────
init_log_dirs() {
    # Créer les répertoires nécessaires
    mkdir -p "$LOG_DIR" "$LOG_ARCHIVE_DIR"

    # Permissions : répertoire principal lisible par tous, archives restreintes
    chmod 755 "$LOG_DIR"
    chmod 750 "$LOG_ARCHIVE_DIR"

    # Créer les fichiers de log s'ils n'existent pas
    touch "$LOG_MAIN" "$LOG_AUDIT" "$LOG_SECURITY"

    # Permissions : lecture pour tous, écriture par propriétaire uniquement
    chmod 644 "$LOG_MAIN" "$LOG_AUDIT" "$LOG_SECURITY"

    echo "[INFO] Système de logs initialisé dans $LOG_DIR"
}

# ─────────────────────────────────────────────
# Vérifier si un niveau de log est valide
# ─────────────────────────────────────────────
is_valid_level() {
    local level="$1"
    for valid in "${LOG_LEVELS[@]}"; do
        [[ "$level" == "$valid" ]] && return 0
    done
    return 1
}
