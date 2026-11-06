#!/usr/bin/env bash
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export LD_LIBRARY_PATH="$HERE/lib:${LD_LIBRARY_PATH:-}"
export ASAN_OPTIONS=detect_leaks=0:abort_on_error=1:halt_on_error=1:symbolize=1:allocator_may_return_null=1
export UBSAN_OPTIONS=print_stacktrace=1:halt_on_error=1
export PATH="$HERE/bin:$PATH"
