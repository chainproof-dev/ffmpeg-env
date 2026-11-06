# ffmpeg-env — FFmpeg Security Research Environment

**One command loads everything**: 6 prebuilt FFmpeg runtimes (release, debug,
ASan+UBSan, UBSan-strict, FATE-tools-ASan, shared-dev), all their libraries and
dependencies, the `ffenv` CLI, and the complete FFmpeg source repository with
full history (128,000+ commits, all upstream SHAs and tags intact).

Built for PoC testing and security research: triage a crash input across every
sanitizer configuration in a single command, then bisect the exact regression
range in the same repository.

```bash
git clone https://github.com/chainproof-dev/ffmpeg-env.git
cd ffmpeg-env
bash env/scripts/setup.sh        # one-time: fetch + verify all build payloads
source env/env.sh                # ONE COMMAND — everything is on PATH now
```

After `source env/env.sh` every build is callable from anywhere by a unique name:

```bash
ffmpeg-release -version
ffprobe-asan-ubsan -v trace poc.oma
ffenv run-all -i poc.mp4 -f null -          # PoC triage across all 6 builds
```

> The heavy build payloads (binaries reach 480 MB, over git's 100 MB per-file
> limit) are distributed as sha256-verified assets of the
> [`builds-v1` release](https://github.com/chainproof-dev/ffmpeg-env/releases/tag/builds-v1)
> and are installed by `setup.sh` — or fetched automatically on first use of
> any shim. Everything else (scripts, metadata, full FFmpeg source and history)
> is right here in the git tree.

---

## What's inside

| Path | Contents |
|---|---|
| `env/env.sh` | **the one-command loader** (PATH, LD_LIBRARY_PATH, sanitizer defaults, shell helpers) |
| `env/bin/` | 15 shims (`ffmpeg-<variant>`, `ffprobe-<variant>`, `videogen-<variant>`) + the `ffenv` CLI |
| `env/scripts/` | `setup.sh`, `fetch-builds.sh`, `verify-builds.sh`, `gen-shims.sh` |
| `env/builds/<variant>/` | each runtime: `bin/` `lib/` (payload) + `build-info/` (configure flags, config.h, exact commit) + `include/` + `src-snippets/` + `README_RUN.txt` |
| `env/manifest.json`, `env/builds/registry.tsv` | machine-readable build registry (asset URLs, sha256, sizes, artifact IDs) |
| `env/docs/` | [USAGE.md](env/docs/USAGE.md) (deep guide), provenance records, upstream README copy |
| repo root | **full FFmpeg source** in native upstream layout — `git log`, `blame`, `bisect` and every upstream SHA/tag work exactly like a plain FFmpeg clone |

## The six runtimes

All built from **ffmpeg@`5d85b7bfb2`** (upstream master, 2026-11-06) on
linux-x86_64 by [chainproof-dev/build run #45](https://github.com/chainproof-dev/build/actions/runs/42171320091):

| Variant | Shim prefix | Use it for |
|---|---|---|
| `release` | `ffmpeg-release` … | optimized build — functionality / baseline behavior |
| `debug` | `ffmpeg-debug` … | symbols + assertions — gdb, backtraces |
| `asan-ubsan` | `ffmpeg-asan-ubsan` … | memory-corruption PoC triage (primary) |
| `ubsan-strict` | `ffmpeg-ubsan-strict` … | halts on first undefined behavior |
| `fate-tools-asan` | `ffmpeg-fate-tools-asan` … | ASan + FATE tools + `videogen` PoC generator |
| `shared-dev` | `ffmpeg-shared-dev` … | `.so` libs + headers — link custom harnesses against libav* |

Run `ffenv list` for the live status table and `ffenv info <variant>` for full
details (asset URL, sha256, configure flags).

## PoC triage in one command

```bash
source env/env.sh

# generate a test input with the bundled FATE tool
videogen-fate-tools-asan /tmp/poc.yuv 320 240
ffmpeg-release -f rawvideo -pix_fmt yuv420p -s 320x240 -i /tmp/poc.yuv -c:v ffv1 /tmp/poc.mkv

# run one input across ALL six runtimes; exit codes + sanitizer hits per variant
ffenv run-all -i /tmp/poc.mkv -f null -
```

`run-all` writes per-variant logs to `/tmp/ffenv-runall/` and greps them for
`ERROR: AddressSanitizer`, `runtime error:` (UBSan), LeakSanitizer reports and
failed assertions — the quick way to see which sanitizer configuration a PoC
trips and how reproducible it is.

## Browsing the FFmpeg source

The repo root *is* a full FFmpeg clone (plus `env/`), so everything upstream
just works:

```bash
git log --oneline -- libavcodec/utils.c | head   # 1600+ commits of file history
git blame libavformat/mov.c
git tag -l 'n7.*'                                # all release tags
git show 5d85b7bfb2                              # exact commit all builds were made from
git checkout n7.1 && git checkout main           # any historical version
```

The `ffmpeg-upstream` branch tracks the merged upstream master (`5d85b7bf`);
merge future upstream updates directly into `main`.

## ffenv reference

```
ffenv list                  status of all variants
ffenv use <variant>         print `export PATH=...` line (or use ffenv-use in sourced shells)
ffenv run <variant> <tool>  run one tool from one variant, e.g. ffenv run debug ffprobe -v trace x.mov
ffenv run-all [tool] [args] run across all variants — PoC triage (FFENV_TIMEOUT, FFENV_LOGDIR)
ffenv fetch [variant ...]   (re)download payloads from the release
ffenv doctor                health check (versions, .so resolution)
ffenv info [variant]        manifest details for one/all variants
```

Full guide with sanitizer tuning, bisect workflows and linking custom tools
against the shared-dev libs: **[env/docs/USAGE.md](env/docs/USAGE.md)**.

## Provenance

* Builds: `chainproof-dev/build` Actions run
  [#42171320091](https://github.com/chainproof-dev/build/actions/runs/42171320091)
  ("Build FFmpeg Security Runtimes", run #45, success, 2026-11-06), workflow_dispatched
  by `chainproof-dev`; artifacts downloaded via the GitHub API and re-verified
  (sha256 per variant, recorded in `env/manifest.json`).
* Each variant's `build-info/` carries the CI's own `config.sh`, `config.h`,
  `config.mak`, `config.log` and `FFMPEG_COMMIT.txt`.
* Original artifact metadata and checksums: `env/docs/provenance/`.
* FFmpeg source: https://github.com/FFmpeg/FFmpeg (LGPL 2.1+ / GPL 2+ where
  enabled — license files at the repo root; source inclusion satisfies the
  redistribution terms for the binaries).

## Notes for agents

* Work from any directory — shims resolve the repo root themselves; symlinking
  `env/bin/*` into `~/.local/bin` also works.
* `FFENV_AUTO_FETCH=0` disables auto-download of missing payloads.
* Set `GH_TOKEN` if the repository is made private; `fetch-builds.sh` picks it up.
* Rebuilding any variant from source: use the exact `configure` line in
  `env/builds/<variant>/build-info/config.sh` against the source at the repo root.
