#!/usr/bin/env bash
# execute_secure.sh — Gestion des cas U1 à U5
# Tâche : T2 | Responsable : khalid 
# Dépend de : lib/interfaces.sh (analyze_command, log_event, log_audit)
#             lib/subshell_exec.sh (init_tmpdir, run_in_subshell, get_stdout, get_stderr, cleanup_tmpdir)
#             lib/timeout_watcher.sh (watch_process, get_return_code)

# ============================================================
# Cas d'utilisation :
#
#   U1 — ALLOW, score < 5   : exécution directe, log INFO
#   U2 — WARN,  score 5–7   : avertissement + confirmation interactive
#   U3 — BLOCK              : refus immédiat (admin peut forcer)
#   U4 — score ≥ 8 non-BLOCK: blocage sécurité (pattern dangereux)
#   U5 — Timeout            : commande tuée après $DOUANES_TIMEOUT secondes
# ============================================================

# Couleurs (désactivées si pas de terminal)
if [[ -t 2 ]]; then
    _RED='\033[0;31m' ; _YEL='\033[1;33m' ; _GRN='\033[0;32m'
    _CYN='\033[0;36m' ; _BLD='\033[1m'    ; _RST='\033[0m'
else
    _RED='' ; _YEL='' ; _GRN='' ; _CYN='' ; _BLD='' ; _RST=''
fi

EXECUTE_SECURE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [[ -f "$EXECUTE_SECURE_DIR/analyze_command.sh" ]]; then
    source "$EXECUTE_SECURE_DIR/analyze_command.sh"
fi

prompt_confirm() {
    local prompt="$1"
    local answer

    if [[ -r /dev/tty && -w /dev/tty ]]; then
        printf "%s" "$prompt" > /dev/tty
        if ! IFS= read -r answer < /dev/tty; then
            answer="n"
        fi
    else
        printf "%s" "$prompt" >&2
        if ! IFS= read -r answer; then
            answer="n"
        fi
    fi

    printf '%s\n' "$answer"
}

# =============================================================================
# execute_secure CMD [ROLE]
#
#   Point d'entrée principal pour l'exécution sécurisée.
#   Analyse la commande, décide du traitement, exécute avec surveillance
#   timeout, affiche stdout et logge le résultat.
#
#   Paramètres :
#     $1  cmd   — Commande à exécuter (chaîne)
#     $2  role  — (optionnel) Rôle : "admin" | "user"  (défaut : "user")
#
#   Retour :
#     0   — Exécution réussie
#     2   — Commande bloquée (sécurité)
#     255 — Timeout
#     N   — Autre code d'erreur de la commande
# =============================================================================
execute_secure() {
    local cmd="${1:?execute_secure: commande requise}"
    local role="${2:-user}"
    local analysis decision rest score reasons rc=0

    # ── Étape 1 : Analyse via T1 ──────────────────────────────────────────
    analysis="$(analyze_command "$cmd" "$role")"
    decision="${analysis%%|*}"
    rest="${analysis#*|}"
    score="${rest%%|*}"
    reasons="${rest##*|}"

    # ── Étape 2 : Décision — cas U1 / U2 / U3 / U4 ───────────────────────
    case "$decision" in

        # ── U3 : BLOCK ────────────────────────────────────────────────────
        BLOCK)
            if [[ "$role" == "admin" ]]; then
                echo -e "${_YEL}[WARN]${_RST} Commande bloquée exécutée par admin : $cmd" >&2
                log_event "ADMIN_OVERRIDE" "$cmd" "$score" "Admin force exec: $reasons"
                log_audit  "ADMIN_OVERRIDE" "cmd=$cmd score=$score raison=$reasons"
                # Continue vers l'exécution ci-dessous
            else
                # ── U3 : refus utilisateur standard ──
                echo -e "${_RED}${_BLD}[BLOCK]${_RST} Commande interdite. Accès refusé." >&2
                echo -e "${_RED}[BLOCK]${_RST} Raison : $reasons" >&2
                log_event "BLOCK" "$cmd" "$score" "$reasons"
                return 2
            fi
            ;;

        # ── U4 : WARN avec score ≥ 8 → pattern dangereux, blocage ─────────
        WARN)
            if (( score >= 8 )); then
                if [[ "$role" != "admin" ]]; then
                    echo -e "${_RED}${_BLD}[SECURITY]${_RST} Pattern dangereux détecté !" >&2
                    echo -e "${_RED}[SECURITY]${_RST} Score : ${score}/10 — $reasons" >&2
                    log_event "SECURITY" "$cmd" "$score" "Pattern dangereux: $reasons"
                    return 2
                fi

                echo -e "${_YEL}${_BLD}[ADMIN-WARN]${_RST} Commande critique détectée." >&2
                echo -e "${_YEL}[ADMIN-WARN]${_RST} Score : ${score}/10 — $reasons" >&2
                log_event "ADMIN_OVERRIDE" "$cmd" "$score" "Confirmation admin requise: $reasons"

                local admin_confirm
                echo -e "${_YEL}Admin, confirmer l'exécution ?${_RST}" >&2
                admin_confirm="$(prompt_confirm "Tapez o pour confirmer, n pour annuler : ")"
                if [[ "$admin_confirm" != "o" && "$admin_confirm" != "O" ]]; then
                    echo -e "${_CYN}[INFO]${_RST} Exécution annulée par l'admin." >&2
                    log_audit "ADMIN_CRITICAL_CANCELLED" "cmd=$cmd score=$score raison=$reasons"
                    return 0
                fi

                log_audit "ADMIN_CRITICAL_ACCEPTED" "cmd=$cmd score=$score raison=$reasons"
            else

            # ── U2 : WARN avec score 5–7 → confirmation interactive ────────
            echo -e "${_YEL}${_BLD}[WARNING]${_RST} Commande à risque modéré." >&2
            echo -e "${_YEL}[WARNING]${_RST} Score : ${score}/10 — $reasons" >&2
            log_event "WARN" "$cmd" "$score" "$reasons"

            local confirm
            echo -e "${_YEL}Confirmer l'exécution ?${_RST}" >&2
            confirm="$(prompt_confirm "Tapez o pour confirmer, n pour annuler : ")"
            if [[ "$confirm" != "o" && "$confirm" != "O" ]]; then
                echo -e "${_CYN}[INFO]${_RST} Exécution annulée par l'utilisateur." >&2
                log_event "CANCELLED" "$cmd" "$score" "Annulée après avertissement"
                return 0
            fi
            log_event "WARN_ACCEPTED" "$cmd" "$score" "Avertissement accepté"
            fi
            ;;

        # ── U1 : ALLOW ────────────────────────────────────────────────────
        ALLOW)
            log_event "ALLOW" "$cmd" "$score" "$reasons"
            ;;

        *)
            echo -e "${_RED}[ERROR]${_RST} Décision inconnue : $decision" >&2
            log_event "ERROR" "$cmd" "$score" "Décision inconnue: $decision"
            return 1
            ;;
    esac

    # ── Étape 3 : Exécution avec surveillance timeout (U1/U2/admin + U5) ──
    log_event "EXEC_START" "$cmd" "$score" "Lancement en sous-shell surveillé"
    init_tmpdir

    watch_process "$cmd" "${DOUANES_TIMEOUT:-30}"
    rc=$?

    # ── Étape 4 : Affichage stdout + résultat ─────────────────────────────
    local stdout_out stderr_out
    stdout_out="$(get_stdout)"
    stderr_out="$(get_stderr)"

    [[ -n "$stdout_out" ]] && echo "$stdout_out"
    [[ -n "$stderr_out" ]] && echo -e "${_YEL}[STDERR]${_RST}" >&2 && echo "$stderr_out" >&2

    local rc_label
    rc_label="$(get_return_code "$rc")"

    if [[ "$rc" -eq 255 ]]; then
        # ── U5 : Timeout ──
        echo -e "${_RED}${_BLD}[TIMEOUT]${_RST} Commande interrompue après ${DOUANES_TIMEOUT:-30}s." >&2
        log_event "TIMEOUT" "$cmd" "$score" "Commande tuée (rc=255)"
    elif [[ "$rc" -eq 0 ]]; then
        echo -e "${_GRN}[OK]${_RST} Exécution réussie."
        log_event "EXEC_OK" "$cmd" "$score" "Réussie ($rc_label)"
    else
        # ── U5 variante : erreur d'exécution ──
        echo -e "${_YEL}[ERROR]${_RST} Exécution échouée (rc=$rc, $rc_label)" >&2
        log_event "EXEC_FAIL" "$cmd" "$score" "Code retour: $rc ($rc_label)"
    fi

    cleanup_tmpdir
    return "$rc"
}
