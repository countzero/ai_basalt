# AGENTS.md

Shares one Basalt setup between machines: Basalt as the submodule `vendor/basalt`, pinned to a
commit of upstream's `main`, and one run config per hardware tier in `presets/`. Basalt publishes
no tags, releases or ready-made engines, so `update_basalt.ps1` moves the submodule to a commit and
builds the engine here; `start.ps1` starts the server with a tier file; `benchmark.ps1` measures
the running server. `README.md` -> *Usage* holds the start command, the other sections the steps
for a new machine, the model pack and the update procedure.

Basalt runs only on NVIDIA Blackwell cards (sm_120) and on Windows on one GPU. A machine without
one stays on ai_strata.

## Tier files

- A tier file is a Basalt config for `basalt serve --config`: a `server` and an `engine` block.
  Name it `<model>.<quant>.<VRAM>_VRAM_<RAM>_RAM.json`, after the hardware, never after a machine.
- `server.model` stays absolute. Other relative paths resolve inside `vendor/basalt`.
- `"host": "0.0.0.0"` without an API key is deliberate: other devices use the server, and
  Basalt only warns about the missing key. Do not narrow the host, and do not add a key.
- `alias` keeps the model name of the matching ai_strata tier, so clients work with either server.
- `port` stays out: `start.ps1` sets it (default 8083, as in ai_strata). Basalt stops at startup
  on an unknown key or a key in the wrong block, so check a new key against
  `vendor/basalt/docs/configuration/index.md` before adding it.
- Change a value only with a `benchmark.ps1` run before and after, on the same Basalt commit.
  The numbers go into `README.md` -> *Tiers* and into the commit message.

## Basalt

- `vendor/basalt` is upstream's code: never edit it here. Its own `AGENTS.md` and `docs/`
  explain the engine and every setting.
- Updates follow `README.md` -> *Update Basalt*, which runs `update_basalt.ps1`. Move only to a
  commit whose `ci` run passed: upstream commits many times a day.
- Never run `basalt-bench --community`: it appends to `vendor/basalt/docs/community/benchmarks.json`.
  `basalt-bench` and `basalt-probe` load the model themselves and need the GPU free.
- The running server is the user's, and other clients depend on it: never stop or restart it,
  nor the Strata server on the same port, without asking.

## Benchmark

`tools/strata/` holds Strata's `strata_bench.py` and the three files it imports, copied from
Strata v0.2.4.2 (MIT, `tools/strata/LICENSE`), so both servers run the same suite. Only
`strata_bench.py` differs from upstream, at the lines marked `ai_basalt`: requests name the served
model, the server check accepts Basalt, and the messages and the report name the server and its
commit. `benchmark.ps1` passes those as `STRATA_BENCH_MODEL`, `STRATA_BENCH_SERVER` and
`STRATA_BENCH_COMMIT`. Keep the copy otherwise byte for byte, and refresh it only together with
ai_strata's Strata version.

## Scratch Files

Agent output, logs and benchmark results go under `.tmp/` at the repository root, which is
gitignored and inside the project. Never into `vendor/basalt`, and not into `%TEMP%`, which
agents may not reach without asking.

## Privacy

No machine names, local user names, IP addresses or paths to a home folder in any file or commit
message. Describe hardware by its parts (GPU, VRAM, RAM, cores).

## Version Control

Semantic Versioning. `CHANGELOG.md` follows Common Changelog and is written only as a step of a
release (`.opencode/skills/release/SKILL.md`).

Commit only when asked, and push only when asked; "commit" does not imply "push". The subject is
one imperative line. The body carries the measurement, the reason, and what was left undone. No
`Co-Authored-By` trailer.

## Output Formatting

Pad every cell of a markdown table so that all cells of a column share one width.
