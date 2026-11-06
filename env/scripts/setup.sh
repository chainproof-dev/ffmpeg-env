#!/usr/bin/env bash
# setup.sh — ONE-COMMAND bootstrap for a fresh clone of ffmpeg-env.
#
#   bash scripts/setup.sh
#
# What it does:
#   1. checks required tools (curl, unzip, sha256sum, ...)
#   2. downloads + verifies all build payloads from the GitHub release
#      (skips any variant that is already installed)
#   3. smoke-tests every build
#
# Afterwards load the environment in your shell with:
#   source /path/to/ffmpeg-env/env.sh
set -euo pipefail

FFENV_LIB_DIR="$(cd -P "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FFENV_ROOT="$(dirname "$FFENV_LIB_DIR")"

echo "============================================================"
echo " ffmpeg-env setup"
echo " root: $FFENV_ROOT"
echo "============================================================"

missing=()
for c in bash curl unzip sha256sum cut sed awk; do
  command -v "$c" >/dev/null 2>&1 || missing+=("$c")
done
if [ "${#missing[@]}" -gt 0 ]; then
  echo "ERROR: missing required tools: ${missing[*]}" >&2
  exit 1
fi
if ! command -v python3 >/dev/null 2>&1; then
  echo "note: python3 not found — 'ffenv info' will fall back to raw JSON"
fi

echo
echo "[1/2] fetching build payloads (release assets) ..."
bash "$FFENV_ROOT/scripts/fetch-builds.sh" "$@"

echo
echo "[2/2] verifying builds ..."
bash "$FFENV_ROOT/scripts/verify-builds.sh"

echo
echo "============================================================"
echo " setup complete."
echo
echo " Load the environment (ONE command, any shell):"
echo "   source $FFENV_ROOT/env.sh"
echo
echo " Then try:"
echo "   ffenv list"
echo "   ffmpeg-release -version"
echo "   ffenv run-all -i poc.mp4 -f null -    # PoC triage"
echo "============================================================"
