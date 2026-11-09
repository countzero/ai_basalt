# Changelog

This changelog follows [Common Changelog](https://common-changelog.org) and this project adheres
to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [2.1.0] - 2026-11-09

_After pulling: stop the server and run `.\update_basalt.ps1 -commit f19f69e68cdb` in PowerShell 7. It builds the engine of that Basalt commit, which reads only version 2 packs and tier files. A pack converted before Basalt `6749fc77` stops the start with a tokenizer error: convert it again as README.md -> *Model pack* says, with `--force`. A later version 1 pack is migrated with `vendor\basalt\tools\migrations\basalt_v1_to_v2.py`._

### Changed
- Move Basalt to `f19f69e68cdb` ([`bbf3d21`](https://github.com/countzero/ai_basalt/commit/bbf3d21), [`df5b2f7`](https://github.com/countzero/ai_basalt/commit/df5b2f7), [`e2daa74`](https://github.com/countzero/ai_basalt/commit/e2daa74), [`b23a693`](https://github.com/countzero/ai_basalt/commit/b23a693), [`e2269b3`](https://github.com/countzero/ai_basalt/commit/e2269b3))
- Write the tier file in Basalt's version 2 config shape, with no value changed ([`b23a693`](https://github.com/countzero/ai_basalt/commit/b23a693))
- Lock the n-gram table in RAM and size the CPU pool on the P-cores, for faster agent decode and no slow first prompt ([`dab80c8`](https://github.com/countzero/ai_basalt/commit/dab80c8))
- Accept images from other devices only as base64 `data:` URLs, unless `image-url-host` or `image-dir` allow more ([`e2daa74`](https://github.com/countzero/ai_basalt/commit/e2daa74))
- Show the build's progress and time left, and log its warnings under `.tmp\build\` ([`a3d6acd`](https://github.com/countzero/ai_basalt/commit/a3d6acd))
- Measure the tier on `f19f69e68cdb`: chat decode may be 7-12 % slower than on `ca7d07418cdf` ([`406ac3b`](https://github.com/countzero/ai_basalt/commit/406ac3b))

### Added
- Add `experiment.ps1`, which measures the tier with changed engine settings, and `-out` to `benchmark.ps1` ([`dab80c8`](https://github.com/countzero/ai_basalt/commit/dab80c8))

### Fixed
- Name the tokenizer error of packs converted before Basalt `6749fc77`, and its cure, in README.md -> *Update Basalt* ([`e2269b3`](https://github.com/countzero/ai_basalt/commit/e2269b3))

## [2.0.0] - 2026-10-27

_After pulling: stop the server and run `.\update_basalt.ps1 -commit b6125f607ece` in PowerShell 7. It builds the engine of that Basalt commit. Basalt now listens on port 8084: point its clients from port 8083 to 8084._

### Changed
- **Breaking:** Move Basalt to port 8084, so it no longer shares port 8083 with ai_strata ([`ab93dc9`](https://github.com/countzero/ai_basalt/commit/ab93dc9))
- Move Basalt to `b6125f607ece` ([`af72b67`](https://github.com/countzero/ai_basalt/commit/af72b67))

## [1.0.0] - 2026-10-25

_Initial release._

### Added
- Pin Basalt `8d73a3947769` as the submodule `vendor/basalt`, and add `update_basalt.ps1`, which builds its engine ([`0947666`](https://github.com/countzero/ai_basalt/commit/0947666))
- Add the 24 GB VRAM / 192 GB RAM tier for Qwen3.8-Flash-Next UD-IQ4_XS, served from a pack converted from Unsloth's GGUF ([`0947666`](https://github.com/countzero/ai_basalt/commit/0947666))
- Add `start.ps1`, and `benchmark.ps1`, which runs Strata's benchmark suite against the running server ([`0947666`](https://github.com/countzero/ai_basalt/commit/0947666))
- Add the agent rules and the plan-review and release skills ([`0947666`](https://github.com/countzero/ai_basalt/commit/0947666))

[2.1.0]: https://github.com/countzero/ai_basalt/releases/tag/v2.1.0
[2.0.0]: https://github.com/countzero/ai_basalt/releases/tag/v2.0.0
[1.0.0]: https://github.com/countzero/ai_basalt/releases/tag/v1.0.0
