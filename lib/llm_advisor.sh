#!/usr/bin/env bash
# llm_advisor.sh - Integration LLM en mode conseiller uniquement
# Tache : T4 | Responsable : H-LAPRIME
# Depend de : interfaces.sh

set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
source "$SCRIPT_DIR/interfaces.sh"

if [[ -f "$PROJECT_DIR/.env" ]]; then
    set -a
    # shellcheck source=/dev/null
    source "$PROJECT_DIR/.env"
    set +a
fi

LLM_PROVIDER="${LLM_PROVIDER:-mistral}"
LLM_API_URL="${LLM_API_URL:-http://localhost:11434/api/generate}"
LLM_MODEL="${LLM_MODEL:-mistral-small-latest}"
MISTRAL_API_URL="${MISTRAL_API_URL:-https://api.mistral.ai/v1/chat/completions}"
MISTRAL_MODEL="${MISTRAL_MODEL:-$LLM_MODEL}"
LLM_TIMEOUT="${LLM_TIMEOUT:-10}"

json_escape() {
    if command -v jq >/dev/null 2>&1; then
        jq -Rs .
    else
        sed \
            -e 's/\\/\\\\/g' \
            -e 's/"/\\"/g' \
            -e ':a;N;$!ba;s/\n/\\n/g' \
            -e 's/^/"/' \
            -e 's/$/"/'
    fi
}

build_security_prompt() {
    local cmd="$1"
    local score="$2"

    cat <<EOF
Tu es un assistant securite Linux. Analyse cette commande :
Commande : $cmd
Score de risque calcule : $score/10

Reponds uniquement avec un JSON valide contenant :
{
  "is_safe": true/false,
  "risk_summary": "resume en une phrase",
  "alternative": "commande plus sure si applicable",
  "explanation": "explication courte"
}
EOF
}

consult_mistral() {
    local cmd="$1"
    local score="$2"
    local prompt
    local payload
    local response
    local llm_text

    if [[ -z "${MISTRAL_API_KEY:-}" ]]; then
        echo "[LLM] MISTRAL_API_KEY manquante."
        echo "[LLM] Exemple : export MISTRAL_API_KEY='ta_cle_api'"
        log_event "WARNING" "$cmd" "$score" "Consultation Mistral impossible: cle absente"
        return 1
    fi

    prompt="$(build_security_prompt "$cmd" "$score")"
    payload="$(printf '{"model":"%s","messages":[{"role":"system","content":"Tu es un conseiller securite Linux. Tu ne dois jamais executer de commande."},{"role":"user","content":%s}],"temperature":0.1,"max_tokens":500}' \
        "$MISTRAL_MODEL" "$(printf '%s' "$prompt" | json_escape)")"

    response="$(curl -s --max-time "$LLM_TIMEOUT" \
        -X POST "$MISTRAL_API_URL" \
        -H "Authorization: Bearer $MISTRAL_API_KEY" \
        -H "Content-Type: application/json" \
        -d "$payload" 2>/dev/null)" || {
        echo "[LLM] Impossible de contacter Mistral."
        log_event "WARNING" "$cmd" "$score" "Consultation Mistral impossible: API indisponible"
        return 1
    }

    if command -v jq >/dev/null 2>&1; then
        llm_text="$(printf '%s' "$response" | jq -r '.choices[0].message.content // .message.content // empty' 2>/dev/null)"
    else
        llm_text="$response"
    fi

    if [[ -z "$llm_text" ]]; then
        echo "[LLM] Reponse Mistral vide ou invalide."
        if command -v jq >/dev/null 2>&1; then
            printf '%s\n' "$response" | jq -r '.error.message // empty' 2>/dev/null
        fi
        log_event "WARNING" "$cmd" "$score" "Consultation Mistral: reponse vide"
        return 1
    fi

    printf '%s\n' "$llm_text"
}

consult_ollama() {
    local cmd="$1"
    local score="$2"
    local prompt
    local payload
    local response
    local llm_text

    prompt="$(build_security_prompt "$cmd" "$score")"
    payload="$(printf '{"model":"%s","prompt":%s,"stream":false}' \
        "$LLM_MODEL" "$(printf '%s' "$prompt" | json_escape)")"

    response="$(curl -s --max-time "$LLM_TIMEOUT" \
        -X POST "$LLM_API_URL" \
        -H "Content-Type: application/json" \
        -d "$payload" 2>/dev/null)" || {
        echo "[LLM] Impossible de contacter le LLM local."
        log_event "WARNING" "$cmd" "$score" "Consultation Ollama impossible: API indisponible"
        return 1
    }

    if command -v jq >/dev/null 2>&1; then
        llm_text="$(printf '%s' "$response" | jq -r '.response // empty' 2>/dev/null)"
    else
        llm_text="$response"
    fi

    if [[ -z "$llm_text" ]]; then
        echo "[LLM] Reponse locale vide ou invalide."
        log_event "WARNING" "$cmd" "$score" "Consultation Ollama: reponse vide"
        return 1
    fi

    printf '%s\n' "$llm_text"
}

# consult_llm CMD SCORE
# Affiche une suggestion de securite. N'execute jamais la proposition du LLM.
consult_llm() {
    local cmd="$1"
    local score="$2"
    local llm_text

    if ! command -v curl >/dev/null 2>&1; then
        echo "[LLM] curl non disponible, consultation ignoree."
        log_event "WARNING" "$cmd" "$score" "Consultation LLM impossible: curl absent"
        return 1
    fi

    case "$LLM_PROVIDER" in
        mistral)
            llm_text="$(consult_mistral "$cmd" "$score")" || return 1
            ;;
        ollama|local)
            llm_text="$(consult_ollama "$cmd" "$score")" || return 1
            ;;
        *)
            echo "[LLM] Provider inconnu : $LLM_PROVIDER"
            echo "[LLM] Utilise LLM_PROVIDER=mistral ou LLM_PROVIDER=ollama."
            return 1
            ;;
    esac

    echo ""
    echo "[LLM Conseiller - $LLM_PROVIDER]"
    if command -v jq >/dev/null 2>&1; then
        printf '%s\n' "$llm_text" | jq . 2>/dev/null || printf '%s\n' "$llm_text"
    else
        printf '%s\n' "$llm_text"
    fi
    echo "[LLM] Note : cette suggestion n'a aucun effet automatique sur l'execution."

    log_event "INFO" "$cmd" "$score" "Consultation LLM effectuee"
}

maybe_consult_llm() {
    local cmd="$1"
    local score="$2"

    if [[ "$score" =~ ^[0-9]+$ ]] && (( score >= 4 && score <= 7 )); then
        consult_llm "$cmd" "$score"
    fi
}
