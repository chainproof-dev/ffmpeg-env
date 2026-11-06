# ffmpeg-env — Deep Usage Guide (for agents & researchers)

Everything below assumes `source env/env.sh` has been run in the current shell
(works from any directory; re-sourcing is safe).

---

## 1. The one-command loader

```bash
source /path/to/ffmpeg-env/env/env.sh
```

What it does:

* puts `env/bin` on `PATH` — 15 shims + the `ffenv` CLI become globally callable
* puts every installed variant's `lib/` dir on `LD_LIBRARY_PATH`
  (matters for `shared-dev`'s `libav*.so`)
* exports `FFMPEG_ENV_ROOT` / `FFENV_ROOT` (env dir), `FFMPEG_SRC` (repo root =
  full ffmpeg source), `FFMPEG_BUILD_ROOT`, `FFENV_MANIFEST`
* sets research-friendly sanitizer defaults (only if you haven't set your own):

  ```
  ASAN_OPTIONS=detect_leaks=0:abort_on_error=1:halt_on_error=1:symbolize=1:allocator_may_return_null=1
  UBSAN_OPTIONS=print_stacktrace=1:halt_on_error=1
  ```

* defines shell helpers: `ffenv-list`, `ffenv-use <variant>`, `ffenv-unuse`

Calling a shim whose payload is not installed yet auto-downloads it from the
release (disable with `FFENV_AUTO_FETCH=0`). Shims also work through symlinks,
so `ln -s $FFENV_ROOT/bin/* ~/.local/bin/` is supported.

## 2. Shims — every build, unique name, any directory

```
ffmpeg-release, ffprobe-release
ffmpeg-debug,   ffprobe-debug
ffmpeg-asan-ubsan,          ffprobe-asan-ubsan,          videogen-asan-ubsan
ffmpeg-ubsan-strict,        ffprobe-ubsan-strict,        videogen-ubsan-strict
ffmpeg-fate-tools-asan,     ffprobe-fate-tools-asan,     videogen-fate-tools-asan
ffmpeg-shared-dev, ffprobe-shared-dev
```

Each shim sets the variant's `LD_LIBRARY_PATH` and sanitizer defaults itself,
so they are self-contained — you can call them from cron, scripts, other users'
shells, anywhere.

Prefer the plain command names (`ffmpeg`, `ffprobe`) resolving to one specific
variant? `ffenv-use asan-ubsan` (function from env.sh) prepends just that
variant's `bin/` to PATH; `ffenv-unuse` reverts. Non-sourced shells:
`eval "$(ffenv use asan-ubsan)"`.

## 3. PoC triage workflow

### 3.1 Single-variant deep dive

```bash
# full parsing trace (classic ffprobe fuzzing style, see README_RUN.txt in each build)
ffprobe-asan-ubsan -v trace poc.oma

# watch for errors only
ffprobe-ubsan-strict -v error cmov_oom.mp4

# decode to null — the standard "does it crash while decoding" test
ffmpeg-asan-ubsan -v error -i poc.mp4 -f null -
```

### 3.2 All variants at once

```bash
ffenv run-all -i poc.mp4 -f null -              # ffmpeg across all 6 runtimes
ffenv run-all ffprobe -v trace poc.mkv          # any tool works
FFENV_TIMEOUT=10 ffenv run-all -i poc.mp4 -f null -     # per-run timeout (default 60s)
FFENV_LOGDIR=/var/tmp/logs ffenv run-all ...             # custom log dir
```

Output: one line per variant with exit code and the first sanitizer hit, e.g.

```
asan-ubsan       rc=1    sanitizer_hits=3   ERROR: AddressSanitizer: heap-buffer-overflow ...
ubsan-strict     rc=134  sanitizer_hits=1   runtime error: left shift of negative value...
release          rc=0    sanitizer_hits=0
```

* `rc=124` → timed out (useful signal: hang/infinite loop PoC)
* `rc=134` → SIGABRT (sanitizer halt / assertion)
* full stdout+stderr per variant: `$FFENV_LOGDIR/<timestamp>-<variant>.log`

`run-all` exits non-zero if any variant exited non-zero — handy in CI gates.

### 3.3 Generating test inputs

`videogen` (bundled with the asan-ubsan, ubsan-strict and fate-tools-asan
variants) is FFmpeg's FATE video generator:

```bash
videogen-fate-tools-asan /tmp/poc.yuv 65536 65536      # raw yuv, W H
ffmpeg-release -f rawvideo -pix_fmt yuv420p -s 64x64 -i /tmp/poc.yuv -c:v ffv1 /tmp/poc.mkv
```

`env/builds/*/src-snippets/` contains the C sources of interesting parsers
(`mov.c`, `matroskadec.c`, `omadec.c`, `http.c`, ...) as shipped by the CI —
handy reading next to a PoC.

## 4. Interpreting sanitizer output

* **ASan** (`asan-ubsan`, `fate-tools-asan`): `ERROR: AddressSanitizer: <class>`
  + a `SUMMARY:` line with the top frame. For symbolized stack traces install
  `llvm-symbolizer` (present on most distros; ASan auto-detects it).
  `allocator_may_return_null=1` keeps huge-allocation PoCs from aborting early.
* **UBSan** (`ubsan-strict`, plus UBSan half of `asan-ubsan`):
  `runtime error: ...` lines with file:line of the UB. `ubsan-strict` halts on
  the first one (`halt_on_error=1`), so `rc != 0` means "UB detected".
* **debug**: assertions are compiled in — `Assertion '...' failed` in the log
  marks an internal-invariant break even without sanitizers.
* Override defaults any time: `ASAN_OPTIONS=detect_leaks=1 ffprobe-asan-ubsan ...`

## 5. Source browsing, history & bisect

The repository root is a complete FFmpeg checkout (native upstream paths),
merged with full history. Everything you'd do in a plain FFmpeg clone works:

```bash
git log --oneline -- libavcodec/hevcdec.c | head
git blame libavformat/mov.c | head
git log -S 'ff_alloc_timecode_metadata_av1' --oneline -- libavcodec/utils.c
git tag -l | rg '^n7'          # release tags
git show n6.0:libavcodec/utils.c | head
```

**Bisecting a regression found by a PoC** — the untracked `env/builds/`
directory survives checkouts, so your testbed stays armed during the whole
bisect:

```bash
git bisect start
git bisect bad  ffmpeg-upstream          # current master (5d85b7bf)
git bisect good n7.0                     # last known good release
# test each step with the ASan runtime against your PoC:
git bisect run bash -c 'ffmpeg-asan-ubsan -v error -i /tmp/poc.mkv -f null - ; test $? -ne 0'
git bisect reset
```

(For crashes that need a build of the checked-out commit, compile in-tree:
`env/builds/asan-ubsan/build-info/config.sh` holds the exact configure line.)

**Finding the fix for a known CVE/advisory commit**: upstream SHAs resolve
directly — `git show <upstream-sha>`. `ffmpeg-upstream` always points at the
merged upstream master tip.

## 6. Linking your own tools against the FFmpeg libs

The `shared-dev` variant ships headers + `.so` libraries:

```bash
gcc my_harness.c -o my_harness \
    -I "$FFENV_ROOT/builds/shared-dev/include" \
    -L "$FFENV_ROOT/builds/shared-dev/lib" \
    -lavformat -lavcodec -lavutil -lswresample -lswscale \
    -lm -lz -pthread
LD_LIBRARY_PATH="$FFENV_ROOT/builds/shared-dev/lib" ./my_harness poc.mp4
```

Static archives of every other variant live in `env/builds/<variant>/lib`
(`libavcodec.a` ...) if you want sanitizer-instrumented static linking.

## 7. Managing payloads

```bash
ffenv fetch                    # download + verify + install all variants
ffenv fetch asan-ubsan         # just one
env/scripts/fetch-builds.sh --force release    # re-install over existing
env/scripts/verify-builds.sh   # smoke test every install
ffenv doctor                   # versions + .so resolution health check
```

Assets come from the `builds-v1` release; each is sha256-verified against
`env/builds/registry.tsv` before extraction. Cache lives in `env/.cache/`
(safe to delete). `GH_TOKEN=<token>` in the environment switches all downloads
to authenticated mode (required only if the repo is private).

## 8. Machine-readable registry

`env/manifest.json` (rich) and `env/builds/registry.tsv` (bash-friendly) list
every variant with: tools, asset URL, sha256, byte size, GitHub artifact ID,
lib type and description. `ffenv info` prints either a summary or full JSON per
variant. Build provenance (run metadata, original sha256 files, CI download
links) is under `env/docs/provenance/`.

## 9. Rebuilding a variant exactly

Each variant's `env/builds/<variant>/build-info/` holds the complete CI build
definition:

* `config.log` — **first line is the exact `./configure` invocation** used at
  CI time (the rest is the full configure probe log)
* `config.sh`, `config.mak`, `config.h` — generated build configuration
* `FFMPEG_COMMIT.txt` — the exact source commit (matches upstream master here)

To reproduce a build:

```bash
git -C "$FFMPEG_SRC" checkout $(cat "$FFENV_ROOT/builds/asan-ubsan/build-info/FFMPEG_COMMIT.txt")
cd "$(mktemp -d)" && cp -a "$FFMPEG_SRC/." .
sed -n '1p' "$FFENV_ROOT/builds/asan-ubsan/build-info/config.log" | sed 's/^# //' | bash -s -- \
    --prefix="$PWD/out"      # re-run the recorded configure line with a local prefix
make -j"$(nproc)" && make install
```

## 10. Layout map

```
ffmpeg-env/
├── README.md                    this environment's overview (repo landing page)
├── <FFmpeg source tree>         full upstream source — libavcodec/ etc. + 128k commits
├── env/
│   ├── env.sh                   ONE-COMMAND loader (source it)
│   ├── bin/                     ffenv CLI + 15 tool shims
│   ├── scripts/                 setup / fetch-builds / verify-builds / gen-shims
│   ├── builds/<variant>/        bin/ lib/ (payload) + build-info/ include/ src-snippets/
│   ├── manifest.json            machine-readable registry
│   └── docs/                    USAGE.md (this file), provenance/, UPSTREAM_README.md
└── ffmpeg-upstream              branch = merged upstream master tip (5d85b7bf)
```
