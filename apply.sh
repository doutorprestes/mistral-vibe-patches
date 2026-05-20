#!/usr/bin/env bash
# mistral-vibe-patches — Bugfix patches for Mistral Vibe CLI
# Copyright (C) 2026  José Augusto de Lima Prestes <doutorprestes@gmail.com>
#
# Patches are derivative works of Mistral Vibe (Apache 2.0).
# Original: https://github.com/mistralai/mistral-vibe
#
# This program is free software under the terms of the
# Apache License, Version 2.0.  See the LICENSE file.
set -euo pipefail

VERSION="1.2.0"
REPO="mistral-vibe-patches"

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
RED='\033[0;31m'
NC='\033[0m'

info()  { echo -e "${CYAN}➜${NC} $1"; }
ok()    { echo -e "${GREEN}✓${NC} $1"; }
warn()  { echo -e "${YELLOW}⚠${NC} $1"; }
fail()  { echo -e "${RED}✘${NC} $1"; exit 1; }

if [ "${1:-}" = "--version" ] || [ "${1:-}" = "-v" ]; then
    echo "mistral-vibe-patches $VERSION"
    exit 0
fi

if [ "${1:-}" = "--help" ] || [ "${1:-}" = "-h" ]; then
    cat <<'EOF'
Usage: apply.sh [OPTIONS]

Apply bugfix patches to an existing Mistral Vibe installation.

Options:
  --path DIR     Explicit path to site-packages (skip auto-detection)
  --reverse      Revert previously applied patches
  --only N       Apply only patch N (e.g. --only 1)
  --version, -v  Show version
  --help, -h     Show this help

Patches:
  1  config-merge    User config takes precedence over project config
  2  reasoning-unset Omit reasoning_effort when thinking is off
EOF
    exit 0
fi

# ── Detect Vibe installation ──────────────────────────────────────────
find_vibe_site_packages() {
    # Try common locations
    for candidate in \
        "$HOME/.local/share/uv/tools/mistral-vibe/lib/python3."*/site-packages \
        "$HOME/.local/pipx/venvs/mistral-vibe/lib/python3."*/site-packages \
        "$HOME/Library/Application Support/uv/tools/mistral-vibe/lib/python3."*/site-packages \
        "/opt/homebrew/lib/python3."*/site-packages/mistral-vibe; do
        for p in $candidate; do
            if [ -d "$p/vibe" ]; then
                echo "$p"
                return 0
            fi
        done
    done
    return 1
}

if [ -n "${1:-}" ] && [ "$1" = "--path" ]; then
    SITE_PKG="$2"
    shift 2
else
    SITE_PKG=$(find_vibe_site_packages) || true
fi

if [ -z "$SITE_PKG" ] || [ ! -d "$SITE_PKG/vibe" ]; then
    fail "Could not detect Mistral Vibe installation.

Install via:  curl -LsSf https://mistral.ai/vibe/install.sh | bash

Then re-run this script, or pass --path <site-packages> explicitly."
fi

VIBE_DIR="$SITE_PKG/vibe"
PATCHES_DIR="$(cd "$(dirname "$0")" && pwd)/patches"

echo ""
echo -e "  ${CYAN}mistral-vibe-patches${NC} v$VERSION"
echo -e "  ${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "  Installation : $SITE_PKG"
echo ""

# ── List patches ──────────────────────────────────────────────────────
ALL_PATCHES=()
if [ -f "$PATCHES_DIR/001-config-merge.patch" ]; then
    ALL_PATCHES+=("$PATCHES_DIR/001-config-merge.patch")
fi
if [ -f "$PATCHES_DIR/002-reasoning-unset.patch" ]; then
    ALL_PATCHES+=("$PATCHES_DIR/002-reasoning-unset.patch")
fi

if [ ${#ALL_PATCHES[@]} -eq 0 ]; then
    fail "No patches found in $PATCHES_DIR"
fi

# ── Parse remaining flags ─────────────────────────────────────────────
ONLY=""
REVERSE=false
while [ $# -gt 0 ]; do
    case "${1:-}" in
        --only)
            shift
            ONLY="${1:-}"
            shift
            ;;
        --reverse)
            REVERSE=true
            shift
            ;;
        *)
            shift  # skip unknown
            ;;
    esac
done

# Filter by patch number
PATCH_LIST=()
if [ -n "$ONLY" ]; then
    case "$ONLY" in
        1) PATCH_LIST=("${ALL_PATCHES[0]}") ;;
        2) PATCH_LIST=("${ALL_PATCHES[1]}") ;;
        *) fail "Invalid patch number: $ONLY (valid: 1, 2)" ;;
    esac
else
    PATCH_LIST=("${ALL_PATCHES[@]}")
fi

RFLAG=""
DIR=""
if $REVERSE; then
    RFLAG="-R"
    DIR="Reversing"
else
    RFLAG=""
    DIR="Applying"
fi

# ── Apply / reverse ───────────────────────────────────────────────────
for PATCH in "${PATCH_LIST[@]}"; do
    NAME=$(basename "$PATCH" .patch)

    # Backups
    while IFS= read -r FILE; do
        REL="${FILE#*/}"
        REL="${REL#*/}"
        TARGET="$VIBE_DIR/$REL"
        if [ -f "$TARGET" ] && [ ! -f "$TARGET.bak" ]; then
            cp "$TARGET" "$TARGET.bak"
            ok "Backup: $(basename $TARGET).bak"
        fi
    done < <(grep '^+++ b/' "$PATCH" || true)

    info "$DIR patch: $NAME..."

    if patch -d "$SITE_PKG" -p1 $RFLAG -i "$PATCH" -t 2>&1 | \
        grep -q "FAILED\|malformed\|Hunk #"; then
        warn "Patch $NAME had issues — check above output."
    else
        ok "Patch $NAME applied successfully."
    fi
done

# ── Verification ──────────────────────────────────────────────────────
echo ""
info "Verifying patches..."

SETTINGS="$VIBE_DIR/core/config/_settings.py"
MISTRAL="$VIBE_DIR/core/llm/backend/mistral.py"

# Verify config-merge: _deep_merge_preserving_lists should exist in _settings.py
if [ -f "$SETTINGS" ]; then
    if grep -q "def _deep_merge_preserving_lists" "$SETTINGS" 2>/dev/null; then
        ok "_deep_merge_preserving_lists method present in settings"
    else
        warn "_deep_merge_preserving_lists not found (may have been reversed)"
    fi
fi

# Verify reasoning: UNSET import should exist
if [ -f "$MISTRAL" ]; then
    if grep -q "from mistralai.client.types.basemodel import UNSET" "$MISTRAL" 2>/dev/null; then
        ok "UNSET import present in mistral backend"
    else
        warn "UNSET import not found (may have been reversed)"
    fi
fi

echo ""
echo -e "  ${GREEN}Done.${NC} Start a new Vibe session and test:"
echo ""
echo -e "    cd ~/your-project  (where .vibe/config.toml exists)"
echo -e "    vibe -p \"What model am I using?\""
echo ""
echo -e "  Your ~/.vibe/config.toml settings should now take precedence."
echo -e "  To revert:  ${CYAN}./apply.sh --reverse${NC}"
echo ""