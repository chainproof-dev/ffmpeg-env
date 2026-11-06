# env.sh — ffmpeg-env ONE-COMMAND loader.
#
#   source /path/to/ffmpeg-env/env.sh
#
# Works from any directory, from any shell (bash/zsh), survives being sourced
# multiple times, and needs no arguments. After sourcing:
#
#   * every build is callable by a unique shim name on PATH:
#       ffmpeg-release, ffmpeg-debug, ffmpeg-asan-ubsan, ffmpeg-ubsan-strict,
#       ffmpeg-fate-tools-asan, ffmpeg-shared-dev   (+ ffprobe-*, videogen-*)
#   * all build library dirs are on LD_LIBRARY_PATH (shared-dev .so etc.)
#   * the ffenv CLI is available (list / use / run / run-all / doctor / info)
#   * FFMPEG_SRC points at the full FFmpeg source checkout (128k+ commits)
#   * sane ASAN_OPTIONS / UBSAN_OPTIONS research defaults are set (overridable)
#
# This file is sourced, NOT executed. Do not run it directly.

if [ -n "${BASH_VERSION:-}" ]; then
  _ffenv_self="${BASH_SOURCE[0]}"
elif [ -n "${ZSH_VERSION:-}" ]; then
  _ffenv_self="${(%):-%x}"
else
  _ffenv_self="$0"
fi
_ffenv_dir="$(cd -P "$(dirname "$_ffenv_self")" && pwd)"
export FFMPEG_ENV_ROOT="$_ffenv_dir"
export FFENV_ROOT="$FFMPEG_ENV_ROOT"

# ---- PATH: shims + ffenv CLI (idempotent) -------------------------------
case ":${PATH}:" in
  *":$FFENV_ROOT/bin:"*) ;;
  *) export PATH="$FFENV_ROOT/bin:$PATH" ;;
esac

# ---- LD_LIBRARY_PATH: every installed variant's lib dir ------------------
_ffenv_ld=""
for _ffenv_libdir in "$FFENV_ROOT"/builds/*/lib; do
  [ -d "$_ffenv_libdir" ] || continue
  case ":${LD_LIBRARY_PATH:-}:" in
    *":$_ffenv_libdir:"*) ;;
    *) _ffenv_ld="$_ffenv_ld:$_ffenv_libdir" ;;
  esac
done
if [ -n "$_ffenv_ld" ]; then
  export LD_LIBRARY_PATH="${_ffenv_ld#:}${LD_LIBRARY_PATH:+:${LD_LIBRARY_PATH}}"
fi

# ---- well-known variables -------------------------------------------------
export FFMPEG_ENV="$FFENV_ROOT"
export FFMPEG_SRC="$FFENV_ROOT/ffmpeg"
export FFMPEG_BUILD_ROOT="$FFENV_ROOT/builds"
export FFENV_MANIFEST="$FFENV_ROOT/manifest.json"
# Research-friendly sanitizer defaults (only affect instrumented builds;
# override by exporting your own values BEFORE sourcing env.sh or a shim call).
export ASAN_OPTIONS="${ASAN_OPTIONS:-detect_leaks=0:abort_on_error=1:halt_on_error=1:symbolize=1:allocator_may_return_null=1}"
export UBSAN_OPTIONS="${UBSAN_OPTIONS:-print_stacktrace=1:halt_on_error=1}"

# ---- shell convenience functions -------------------------------------------
ffenv-list() { command ffenv list "$@"; }

ffenv-use() {  # ffenv-use <variant>  — plain `ffmpeg`/`ffprobe` resolve to this variant
  [ -z "${1:-}" ] && { echo "usage: ffenv-use <variant>   (see: ffenv list)" >&2; return 2; }
  local _v="$1" _bin="$FFENV_ROOT/builds/$1/bin"
  if [ ! -d "$_bin" ]; then
    echo "ffenv: variant '$_v' unknown or not fetched (try: ffenv fetch $_v && ffenv-use $_v)" >&2
    return 1
  fi
  case ":${PATH}:" in
    *":$_bin:"*) ;;
    *) export PATH="$_bin:$PATH" ;;
  esac
  echo "ffenv: plain ffmpeg/ffprobe now resolve to variant '$_v'" >&2
}

ffenv-unuse() {  # remove all variant bin dirs from PATH
  local _p=":$PATH:"
  for _ffenv_vdir in "$FFENV_ROOT"/builds/*/bin; do
    _p="${_p//:$_ffenv_vdir:/:}"
  done
  export PATH="${_p#:}"
  export PATH="${PATH%:}"
  echo "ffenv: variant PATH entries removed" >&2
}

unset _ffenv_self _ffenv_dir _ffenv_ld _ffenv_libdir _ffenv_vdir 2>/dev/null || true

# ---- one-line status --------------------------------------------------------
_ffenv_n=0; _ffenv_r=0
for _ffenv_d in "$FFENV_ROOT"/builds/*/bin; do
  [ -d "$_ffenv_d" ] || continue
  _ffenv_n=$((_ffenv_n + 1))
  [ -x "$_ffenv_d/ffmpeg" ] && _ffenv_r=$((_ffenv_r + 1))
done
echo "ffmpeg-env loaded: $FFENV_ROOT" \
     "($_ffenv_r/$_ffenv_n builds fetched," \
     "ffmpeg @ $(git -C "$FFENV_ROOT/ffmpeg" rev-parse --short HEAD 2>/dev/null || echo n/a))" >&2
echo "  try: ffenv list | ffmpeg-release -version | ffenv run-all -i poc.mp4 -f null -" >&2
unset _ffenv_n _ffenv_r _ffenv_d
