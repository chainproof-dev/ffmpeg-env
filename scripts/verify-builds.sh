#!/usr/bin/env bash
# verify-builds.sh — smoke-test every installed ffmpeg-env build variant:
# runs ffmpeg -version / ffprobe -version and checks shared library resolution.
#
# Usage: scripts/verify-builds.sh
set -euo pipefail

FFENV_LIB_DIR="$(cd -P "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FFENV_ROOT="$(dirname "$FFENV_LIB_DIR")"
# shellcheck source=ffenv-lib.sh
. "$FFENV_LIB_DIR/ffenv-lib.sh"

fails=0
total=0
echo "ffmpeg-env build verification"
echo "======================================================================"
while IFS=$'\t' read -r name tools _u _s _b _a _l _d; do
  ffenv_is_installed "$name" || { printf '%-16s SKIP  (payload not fetched)\n' "$name"; continue; }
  total=$((total + 1))
  commit="$(sed -n '1p' "$FFENV_ROOT/builds/$name/build-info/FFMPEG_COMMIT.txt" 2>/dev/null || echo '?')"
  fver="$(ffenv_run_env "$name" "$FFENV_ROOT/builds/$name/bin/ffmpeg" -version 2>&1 | sed -n '1p' || true)"
  pver="$(ffenv_run_env "$name" "$FFENV_ROOT/builds/$name/bin/ffprobe" -version 2>&1 | sed -n '1p' || true)"
  missing_so=0
  if ls "$FFENV_ROOT/builds/$name/lib/"*.so* >/dev/null 2>&1; then
    missing_so="$(ldd "$FFENV_ROOT/builds/$name/bin/ffmpeg" 2>/dev/null | grep -c 'not found' || true)"
  fi
  if [ -n "$fver" ] && [ -n "$pver" ] && [ "$missing_so" -eq 0 ]; then
    printf '%-16s PASS  ffmpeg@%.10s  ffprobe@%.10s  %s\n' "$name" "$commit" "$commit" "$(echo "$fver" | cut -d' ' -f1-3)"
  else
    printf '%-16s FAIL  ffmpeg@%.10s  ffprobe@%.10s  missing_so=%s\n' "$name" "$commit" "$commit" "$missing_so"
    fails=$((fails + 1))
  fi
done < <(ffenv_registry_rows)
echo "======================================================================"
echo "checked $total build(s), $fails failure(s)"
[ "$fails" -eq 0 ]
