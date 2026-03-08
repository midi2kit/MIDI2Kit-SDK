#!/bin/bash
# Deploy website files to midi2kit.github.io repository
# Usage: ./scripts/deploy-website.sh [commit-message]

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SDK_DIR="$(dirname "$SCRIPT_DIR")"
PAGES_REPO="midi2kit/midi2kit.github.io"
WORK_DIR="/tmp/midi2kit-deploy"
MSG="${1:-"Update website from SDK repo"}"

echo "==> Cloning $PAGES_REPO..."
rm -rf "$WORK_DIR"
gh repo clone "$PAGES_REPO" "$WORK_DIR" -- --depth 1

echo "==> Copying blog files..."
mkdir -p "$WORK_DIR/blog"
cp -r "$SDK_DIR/docs/website/blog/"* "$WORK_DIR/blog/"

echo "==> Done. Files staged in $WORK_DIR"
echo ""
echo "To review and push:"
echo "  cd $WORK_DIR"
echo "  git diff"
echo "  git add -A && git commit -m '$MSG' && git push"
