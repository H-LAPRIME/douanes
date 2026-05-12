#!/usr/bin/env bash
# subshell_exec.sh — Exécution dans un sous-shell isolé
# Tâche : T2 | Responsable : khalid
# Dépend de : rien (module autonome)

# ─── Fichiers temporaires (initialisés par init_tmpdir) ──────────────────────
TMPDIR_EXEC=""
STDOUT_FILE=""
STDERR_FILE=""
RETCODE_FILE=""
PID_FILE=""

# =============================================================================
# init_tmpdir
#   Crée un répertoire temporaire dédié à cette exécution.
#   À appeler AVANT run_in_subshell.
# =============================================================================
init_tmpdir() {
    TMPDIR_EXEC=$(mktemp -d /tmp/douanes_XXXXXX)
    STDOUT_FILE="$TMPDIR_EXEC/stdout"
    STDERR_FILE="$TMPDIR_EXEC/stderr"
    RETCODE_FILE="$TMPDIR_EXEC/retcode"
    PID_FILE="$TMPDIR_EXEC/pid"
    touch "$STDOUT_FILE" "$STDERR_FILE" "$RETCODE_FILE"
}

# =============================================================================
# cleanup_tmpdir
#   Supprime le répertoire temporaire après lecture des résultats.
# =============================================================================
cleanup_tmpdir() {
    [[ -d "$TMPDIR_EXEC" ]] && rm -rf "$TMPDIR_EXEC"
}

# =============================================================================
# run_in_subshell CMD
#
#   Lance CMD dans un sous-shell isolé en arrière-plan.
#
#   Isolation garantie :
#     - Variables sensibles purgées (PASSWORD, TOKEN, API_KEY…)
#     - Alias désactivés
#     - stdout → $STDOUT_FILE
#     - stderr → $STDERR_FILE
#     - code de retour → $RETCODE_FILE
#
#   ⚠ PID écrit dans $PID_FILE (fiable) ET retourné par echo.
#     Toujours lire depuis $PID_FILE côté appelant :
#       run_in_subshell "$cmd" > /dev/null
#       cmd_pid=$(cat "$PID_FILE")
#     (évite la perte du PID dans la substitution de commande $(...))
# =============================================================================
run_in_subshell() {
    local cmd="$1"

    [[ -z "$TMPDIR_EXEC" ]] && init_tmpdir

    (
        # Purger les variables sensibles par nom exact
        unset PASSWORD SECRET TOKEN API_KEY PRIVATE_KEY PASSPHRASE
        unset AWS_SECRET_ACCESS_KEY GITHUB_TOKEN ANTHROPIC_API_KEY
        # Purger aussi toute variable exportée dont le nom matche un mot-clé
        while read -r _v; do
            unset "$_v" 2>/dev/null || true
        done < <(compgen -e | grep -E 'SECRET|PASSWORD|TOKEN|KEY|PASS|PRIVATE')

        # Désactiver les alias (sous-shell uniquement)
        unalias -a 2>/dev/null || true

        # Exécuter en capturant les sorties
        cd "${DOUANES_CALL_DIR:-$PWD}" && eval "$cmd" \
            1>"$STDOUT_FILE" \
            2>"$STDERR_FILE"

        # Sauvegarder le code de retour
        echo $? > "$RETCODE_FILE"
    ) &

    local pid=$!
    echo "$pid" > "$PID_FILE"
    echo "$pid"
}

# =============================================================================
# get_stdout / get_stderr
#   Lit le contenu capturé des sorties.
# =============================================================================
get_stdout() { [[ -f "$STDOUT_FILE" ]] && cat "$STDOUT_FILE" || true; }
get_stderr() { [[ -f "$STDERR_FILE" ]] && cat "$STDERR_FILE" || true; }
