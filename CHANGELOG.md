# Changelog

This changelog follows [Common Changelog](https://common-changelog.org) and this project adheres
to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

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

[2.0.0]: https://github.com/countzero/ai_basalt/releases/tag/v2.0.0
[1.0.0]: https://github.com/countzero/ai_basalt/releases/tag/v1.0.0
