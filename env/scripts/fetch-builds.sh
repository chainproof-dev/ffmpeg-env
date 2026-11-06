#!/usr/bin/env bash
# fetch-builds.sh — download, verify and install ffmpeg-env build payloads.
#
# The heavy binaries/libs of each variant are distributed as assets of the
# GitHub release (tag: builds-v1) because they exceed git's 100 MB per-file
# limit. This script downloads them, verifies sha256 against
# builds/registry.tsv and unpacks them into builds/<variant>/.
#
# Usage:
#   scripts/fetch-builds.sh [--force] [variant ...]     (default: all variants)
#
# Environment:
#   GH_TOKEN      optional; set it if the ffmpeg-env repo is PRIVATE
#   FFENV_CACHE   optional; download cache dir (default: <repo>/.cache)
set -euo pipefail

FFENV_LIB_DIR="$(cd -P "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FFENV_ROOT="$(dirname "$FFENV_LIB_DIR")"
# shellcheck source=ffenv-lib.sh
. "$FFENV_LIB_DIR/ffenv-lib.sh"

CACHE="${FFENV_CACHE:-$FFENV_ROOT/.cache}"
FORCE=0
VARIANTS=()
for arg in "$@"; do
  case "$arg" in
    --force) FORCE=1 ;;
    -h|--help) sed -n '2,20p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) VARIANTS+=("$arg") ;;
  esac
done

CURL_AUTH=()
if [ -n "${GH_TOKEN:-}" ]; then
  CURL_AUTH=(-H "Authorization: Bearer $GH_TOKEN")
fi

download() {  # $1=url $2=dest
  local url="$1" dest="$2" attempt
  mkdir -p "$(dirname "$dest")"
  for attempt in 1 2 3; do
    if curl -fSL ${CURL_AUTH[@]+"${CURL_AUTH[@]}"} -C - --retry 3 --retry-delay 5 \
         --connect-timeout 30 -o "$dest" "$url"; then
      return 0
    fi
    echo "  download failed (attempt $attempt/3), retrying..." >&2
    sleep 5
  done
  return 1
}

install_variant() {  # $1=name $2=asset_url $3=sha256 $4=artifact_name
  local name="$1" url="$2" sha="$3" artifact="$4"
  local dest="$CACHE/$artifact.zip"

  if ffenv_is_installed "$name" && [ "$FORCE" -ne 1 ]; then
    echo "== $name: already installed (use --force to reinstall), skipping"
    return 0
  fi

  echo "== $name: downloading $url"
  download "$url" "$dest"

  echo "   verifying sha256 ..."
  if ! echo "$sha  $dest" | sha256sum -c - >/dev/null 2>&1; then
    echo "   CHECKSUM MISMATCH for $dest — deleting and retrying once" >&2
    rm -f "$dest"
    download "$url" "$dest"
    echo "$sha  $dest" | sha256sum -c - >/dev/null || { echo "   checksum still bad, aborting" >&2; return 1; }
  fi

  echo "   extracting ..."
  local extract="$CACHE/extract-$name"
  rm -rf "$extract"
  mkdir -p "$extract"
  unzip -q "$dest" -d "$extract"
  if [ ! -d "$extract/$name/bin" ]; then
    echo "   unexpected archive layout (missing $name/bin), aborting" >&2
    rm -rf "$extract"
    return 1
  fi

  mkdir -p "$FFENV_ROOT/builds/$name"
  cp -a "$extract/$name/." "$FFENV_ROOT/builds/$name/"
  chmod +x "$FFENV_ROOT/builds/$name"/bin/* 2>/dev/null || true
  rm -rf "$extract"
  echo "   installed -> $FFENV_ROOT/builds/$name"
}

WANT_ALL=0
if [ "${#VARIANTS[@]}" -eq 0 ]; then WANT_ALL=1; fi

rc=0
while IFS=$'\t' read -r name tools url sha bytes artifact_id lib_type desc; do
  if [ "$WANT_ALL" -ne 1 ]; then
    keep=0
    for v in "${VARIANTS[@]}"; do [ "$v" = "$name" ] && keep=1; done
    [ "$keep" -eq 1 ] || continue
  fi
  artifact="ffmpeg-$name-x64-linux"
  install_variant "$name" "$url" "$sha" "$artifact" || rc=1
done < <(ffenv_registry_rows)

if [ "$rc" -ne 0 ]; then
  echo "fetch-builds: one or more variants failed" >&2
  exit 1
fi

echo
echo "All requested build payloads installed."
echo "Load the environment:  source $FFENV_ROOT/env.sh"
echo "Verify:                ffenv doctor"
