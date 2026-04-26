#!/usr/bin/env bash
set -euo pipefail

# Magic Stick — Persistence Survival Mock Test
# Valide statiquement que update-system.sh ne touche jamais la partition
# persistence (n°3 / label persistence) hors du setup initial.
# Ce test est concu pour les runners CI/CD non-privileged (pas de loop device).
#
# Usage: ./test-persistence-mock.sh [path/to/update-system.sh]

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
UPDATE_SCRIPT="${1:-${SCRIPT_DIR}/update-system.sh}"

ERRORS=0
die()  { echo "ERROR: $*" >&2; ((ERRORS++)); }
pass() { echo "  [OK] $*"; }
warn() { echo "  [WARN] $*" >&2; }
fail() { echo "  [FAIL] $*" >&2; ((ERRORS++)); }
info() { echo "==> $*"; }

[[ -f "$UPDATE_SCRIPT" ]] || die "File not found: $UPDATE_SCRIPT"

info "Running persistence survival mock test on ${UPDATE_SCRIPT}"
echo ""

# 1. Syntax check
info "[1/6] Syntax check"
if bash -n "$UPDATE_SCRIPT"; then
    pass "bash -n OK"
else
    fail "bash -n FAILED"
fi
echo ""

# 2. Verify PERSISTENCE_LABEL is defined and equals "persistence"
info "[2/6] PERSISTENCE_LABEL definition"
LABEL=$(grep -E '^PERSISTENCE_LABEL=' "$UPDATE_SCRIPT" | head -1 | cut -d= -f2 | tr -d '"')
if [[ "$LABEL" == "persistence" ]]; then
    pass "PERSISTENCE_LABEL='persistence'"
else
    fail "PERSISTENCE_LABEL missing or unexpected value: '${LABEL}'"
fi
echo ""

# 3. grep for dangerous commands targeting partition 3 OUTSIDE setup context
# We exclude cmd_setup_ab (which legitimately formats p3 during initial setup)
info "[3/6] No destructive commands on persistence partition outside setup"

# Extract the line numbers of cmd_setup_ab boundaries
SETUP_AB_START=$(grep -n 'cmd_setup_ab()' "$UPDATE_SCRIPT" | head -1 | cut -d: -f1)
SETUP_AB_END=$(awk -v start="$SETUP_AB_START" 'NR>=start && /^}/ {print NR; exit}' "$UPDATE_SCRIPT")

# Temp file: script body WITHOUT cmd_setup_ab
TMP_SCRIPT=$(mktemp)
awk -v start="$SETUP_AB_START" -v end="$SETUP_AB_END" 'NR < start || NR > end' "$UPDATE_SCRIPT" > "$TMP_SCRIPT"

# Patterns that must NOT appear outside cmd_setup_ab
PATTERNS=(
    'mkfs.*persistence'
    'mkfs.*\\b${prefix}3\\b'
    'mkfs.*\\bp3\\b'
    'parted.*mkpart.*persistence'
    'dd .*\\b${prefix}3\\b'
    'dd .*\\bp3\\b'
)

for pat in "${PATTERNS[@]}"; do
    if grep -qE "$pat" "$TMP_SCRIPT"; then
        grep -nE "$pat" "$TMP_SCRIPT" | while read -r line; do
            fail "Forbidden pattern outside setup: ${line}"
        done
    fi
done

if [[ "$ERRORS" -eq 0 ]]; then
    pass "No destructive command found outside cmd_setup_ab"
fi
echo ""

# 4. Verify mount/umount of partition 3 is read-only (ro) outside setup
info "[4/6] Partition 3 mount is read-only outside setup"
# Any 'mount' of p3/${prefix}3 outside setup_ab must include '-o ro' or 'mount -o ro'
# If found without '-o ro', that's a failure
 AWK_SCRIPT='
NR >= start && NR <= end {next}
/mount.*\${prefix}3/ || /mount.*p3/ {
    if ($0 !~ /-o[[:space:]]+ro/) {
        print NR": "$0
    }
}'
MOUNT_RW=$(awk -v start="$SETUP_AB_START" -v end="$SETUP_AB_END" "$AWK_SCRIPT" "$UPDATE_SCRIPT" || true)
if [[ -n "$MOUNT_RW" ]]; then
    echo "$MOUNT_RW" | while read -r line; do
        fail "Partition 3 mounted without -o ro outside setup: ${line}"
    done
else
    pass "Partition 3 is never mounted rw outside cmd_setup_ab"
fi
echo ""

# 5. Verify cmd_install and cmd_update only target partitions 1 and 2
info "[5/6] cmd_install / cmd_update target only partitions 1 and 2"

for func in cmd_install cmd_update; do
    FUNC_START=$(grep -n "^${func}()" "$UPDATE_SCRIPT" | head -1 | cut -d: -f1)
    FUNC_END=$(awk -v start="$FUNC_START" 'NR>=start && /^}/ {print NR; exit}' "$UPDATE_SCRIPT")
    
    # Extract function body
    FUNC_BODY=$(mktemp)
    awk -v start="$FUNC_START" -v end="$FUNC_END" 'NR >= start && NR <= end' "$UPDATE_SCRIPT" > "$FUNC_BODY"
    
    # Check for any reference to partition 3 within the function
    # Exclude lines that are purely user-facing messages (echo, cat, comments)
    if grep -vE '^[[:space:]]*(echo|cat|#)' "$FUNC_BODY" | grep -qE '\${prefix}3|\bp3\b|persistence.*partition|partition.*persistence'; then
        fail "${func} references partition 3 or persistence"
        grep -nE '\${prefix}3|\bp3\b|persistence.*partition|partition.*persistence' "$FUNC_BODY" | while read -r line; do
            echo "      ${line}"
        done
    else
        pass "${func} does not reference partition 3"
    fi
    
    rm -f "$FUNC_BODY"
done
echo ""

# 6. Verify user-facing messages confirm persistence is safe
info "[6/6] User-facing messages confirm persistence safety"
MESSAGES=(
    "The persistence partition will NOT be touched"
    "Persistence partition was NOT modified"
    "User data (never touched by updates)"
)
FOUND=0
for msg in "${MESSAGES[@]}"; do
    if grep -qF "$msg" "$UPDATE_SCRIPT"; then
        pass "Message found: '${msg}'"
        FOUND=$((FOUND + 1))
    fi
done

if [[ "$FOUND" -eq 0 ]]; then
    warn "No persistence safety message found — consider adding one"
fi
echo ""

# Cleanup
rm -f "$TMP_SCRIPT"

# Summary
echo "=== Persistence Survival Mock Test ==="
if [[ "$ERRORS" -eq 0 ]]; then
    echo "Result: ALL CHECKS PASSED"
    echo "  update-system.sh does not touch persistence partition outside setup."
    exit 0
else
    echo "Result: ${ERRORS} CHECK(S) FAILED"
    exit 1
fi
