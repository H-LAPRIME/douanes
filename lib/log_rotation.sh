#!/usr/bin/env bash
# log_rotation.sh — Rotation et archivage automatique des logs
# Tâche : T3 | Responsable : aymane
# Dépend de : logger_config.sh

source "$(dirname "${BASH_SOURCE[0]}")/logger_config.sh"

# ═══════════════════════════════════════════════════════════════════
# rotate_log_if_needed LOGFILE
#
# Vérifie la taille du fichier et déclenche une rotation si elle
# dépasse LOG_MAX_SIZE (défaut : 5 Mo).
#
# Arguments :
#   $1  LOGFILE — Chemin absolu vers le fichier de log à surveiller
#
# Retour :
#   0 — aucune rotation nécessaire, ou rotation réussie
#   1 — fichier introuvable
# ═══════════════════════════════════════════════════════════════════
rotate_log_if_needed() {
    local logfile="$1"

    if [[ ! -f "$logfile" ]]; then
        return 1
    fi

    local filesize
    filesize=$(stat -c%s "$logfile" 2>/dev/null || echo 0)

    if (( filesize > LOG_MAX_SIZE )); then
        rotate_log "$logfile"
    fi

    return 0
}

# ═══════════════════════════════════════════════════════════════════
# rotate_log LOGFILE
#
# Effectue la rotation d'un fichier de log :
#   1. Compresse l'ancien fichier en .log.gz horodaté dans archives/
#   2. Vide le fichier courant (sans le supprimer — conserve les droits)
#   3. Supprime les archives les plus anciennes si LOG_MAX_ARCHIVES dépassé
#
# Arguments :
#   $1  LOGFILE — Chemin absolu vers le fichier de log à archiver
#
# Retour :
#   0 — succès
#   1 — erreur (compression ou écriture)
# ═══════════════════════════════════════════════════════════════════
rotate_log() {
    local logfile="$1"

    if [[ ! -f "$logfile" ]]; then
        echo "[log_rotation.sh] ERREUR : fichier introuvable : $logfile" >&2
        return 1
    fi

    local ts
    ts=$(date '+%Y%m%d_%H%M%S')

    local basename
    basename=$(basename "$logfile" .log)

    local archive="$LOG_ARCHIVE_DIR/${basename}_${ts}.log.gz"

    # Comprimer l'ancien log dans le répertoire d'archives
    if ! gzip -c "$logfile" > "$archive" 2>/dev/null; then
        echo "[log_rotation.sh] ERREUR : compression échouée pour $logfile" >&2
        return 1
    fi

    # Vider le fichier courant sans le supprimer (conserve propriétaire et permissions)
    > "$logfile"

    # Supprimer les archives excédentaires (garder les N plus récentes)
    _prune_old_archives "$basename"

    echo "[INFO] Log archivé : $archive"
    return 0
}

# ═══════════════════════════════════════════════════════════════════
# _prune_old_archives BASENAME
#
# Fonction interne — supprime les archives les plus anciennes si le
# nombre d'archives dépasse LOG_MAX_ARCHIVES.
#
# Arguments :
#   $1  BASENAME — Préfixe du nom de fichier (ex: "douanes", "audit")
# ═══════════════════════════════════════════════════════════════════
_prune_old_archives() {
    local basename="$1"
    local pattern="$LOG_ARCHIVE_DIR/${basename}_*.log.gz"

    local count
    count=$(ls $pattern 2>/dev/null | wc -l)

    if (( count > LOG_MAX_ARCHIVES )); then
        # Lister par ordre décroissant de date, supprimer les plus anciennes
        ls -t $pattern 2>/dev/null \
            | tail -n "+$((LOG_MAX_ARCHIVES + 1))" \
            | xargs rm -f --
        echo "[INFO] Archives excédentaires supprimées pour : $basename"
    fi
}

# ═══════════════════════════════════════════════════════════════════
# archive_logs
#
# Archivage manuel complet — réservé à l'admin (cas A4).
# Crée une archive .tar.gz de tous les fichiers de log courants
# dans le répertoire d'archives, avec horodatage.
#
# Retour :
#   0 — succès
#   1 — erreur de création d'archive
# ═══════════════════════════════════════════════════════════════════
archive_logs() {
    local ts
    ts=$(date '+%Y%m%d_%H%M%S')
    local archive_path="$LOG_ARCHIVE_DIR/manual_${ts}.tar.gz"

    # Créer le répertoire d'archives si inexistant
    mkdir -p "$LOG_ARCHIVE_DIR"

    # Archiver tous les .log du répertoire principal
    if ! tar -czf "$archive_path" \
        -C "$LOG_DIR" \
        --exclude='archives' \
        --exclude='*.gz' \
        $(ls "$LOG_DIR"/*.log 2>/dev/null | xargs -n1 basename 2>/dev/null) \
        2>/dev/null
    then
        echo "[log_rotation.sh] ERREUR : création de l'archive manuelle échouée." >&2
        return 1
    fi

    echo "[INFO] Archive manuelle créée : $archive_path"
    return 0
}

# ═══════════════════════════════════════════════════════════════════
# list_archives [BASENAME]
#
# Liste les archives disponibles, optionnellement filtrées par basename.
# Usage interne / admin.
# ═══════════════════════════════════════════════════════════════════
list_archives() {
    local basename="${1:-}"
    local pattern

    if [[ -n "$basename" ]]; then
        pattern="$LOG_ARCHIVE_DIR/${basename}_*.log.gz"
    else
        pattern="$LOG_ARCHIVE_DIR/*.gz"
    fi

    if ls $pattern 2>/dev/null | grep -q .; then
        echo "[INFO] Archives disponibles :"
        ls -lh $pattern 2>/dev/null
    else
        echo "[INFO] Aucune archive trouvée."
    fi
}

# ═══════════════════════════════════════════════════════════════════
# Bloc de test autonome
# ═══════════════════════════════════════════════════════════════════
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    echo "=== Test autonome de log_rotation.sh ==="

    init_log_dirs

    echo "--- Test rotate_log_if_needed (fichier sous le seuil) ---"
    echo "Ligne test" >> "$LOG_MAIN"
    rotate_log_if_needed "$LOG_MAIN"
    echo "Aucune rotation attendue (fichier trop petit)."

    echo ""
    echo "--- Test archive_logs (archivage manuel admin) ---"
    archive_logs
    list_archives

    echo ""
    echo "--- Test rotate_log (rotation forcée) ---"
    rotate_log "$LOG_MAIN"
    list_archives "douanes"
fi
