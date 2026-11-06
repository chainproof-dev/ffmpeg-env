#!/usr/bin/env bash
# ffenv-lib.sh — shared helpers for ffmpeg-env scripts (sourced, not executed).
# shellcheck shell=bash disable=SC2034

FFENV_LIB_DIR="$(cd -P "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FFENV_ROOT="${FFENV_ROOT:-$(dirname "$FFENV_LIB_DIR")}"
FFENV_REGISTRY="$FFENV_ROOT/builds/registry.tsv"
FFENV_MANIFEST="$FFENV_ROOT/manifest.json"

ffenv_default_asan() {
  echo "detect_leaks=0:abort_on_error=1:halt_on_error=1:symbolize=1:allocator_may_return_null=1"
}
ffenv_default_ubsan() {
  echo "print_stacktrace=1:halt_on_error=1"
}

# Iterate registry rows: name, tools, asset_url, sha256, bytes, artifact_id, lib_type, description
ffenv_registry_rows() {
  [ -f "$FFENV_REGISTRY" ] && sed -n '2,$p' "$FFENV_REGISTRY"
}

ffenv_variant_names() {
  ffenv_registry_rows | cut -f1
}

ffenv_variant_tools() {  # $1 = variant name
  ffenv_registry_rows | awk -F'\t' -v v="$1" '$1 == v {print $2}'
}

ffenv_variant_field() {  # $1 = variant, $2 = field number (3=url, 4=sha, 5=bytes, 6=artifact_id, 7=lib_type, 8=desc)
  ffenv_registry_rows | awk -F'\t' -v v="$1" '$1 == v {print $'"$2"'}'
}

ffenv_is_installed() {  # $1 = variant
  [ -x "$FFENV_ROOT/builds/$1/bin/ffmpeg" ]
}

ffenv_variant_count() {
  ffenv_variant_names | wc -l
}

# Set runtime env (LD_LIBRARY_PATH + sanitizer defaults) for a variant bin dir — used by verify/doctor.
ffenv_run_env() {  # $1 = variant, remaining = command + args
  local v="$1"; shift
  local libdir="$FFENV_ROOT/builds/$v/lib"
  if [ -d "$libdir" ]; then
    case ":${LD_LIBRARY_PATH:-}:" in
      *":$libdir:"*) ;;
      *) export LD_LIBRARY_PATH="$libdir${LD_LIBRARY_PATH:+:${LD_LIBRARY_PATH}}" ;;
    esac
  fi
  export ASAN_OPTIONS="${ASAN_OPTIONS:-$(ffenv_default_asan)}"
  export UBSAN_OPTIONS="${UBSAN_OPTIONS:-$(ffenv_default_ubsan)}"
  "$@"
}
