# Changelog

This changelog follows [Common Changelog](https://common-changelog.org) and this project adheres
to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [1.0.0] - 2026-10-25

_Initial release._

### Added
- Pin Basalt `8d73a3947769` as the submodule `vendor/basalt`, and add `update_basalt.ps1`, which builds its engine ([`0947666`](https://github.com/countzero/ai_basalt/commit/0947666))
- Add the 24 GB VRAM / 192 GB RAM tier for Qwen3.8-Flash-Next UD-IQ4_XS, served from a pack converted from Unsloth's GGUF ([`0947666`](https://github.com/countzero/ai_basalt/commit/0947666))
- Add `start.ps1`, and `benchmark.ps1`, which runs Strata's benchmark suite against the running server ([`0947666`](https://github.com/countzero/ai_basalt/commit/0947666))
- Add the agent rules and the plan-review and release skills ([`0947666`](https://github.com/countzero/ai_basalt/commit/0947666))

[1.0.0]: https://github.com/countzero/ai_basalt/releases/tag/v1.0.0
