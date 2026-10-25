---
name: release
description: Cut, publish and verify a release of this repository. Use when the user asks for a release, a new version or a tag. Checks the preconditions, drafts the CHANGELOG.md section and the version for the user to confirm, then commits, pushes, publishes the GitHub release and verifies it.
---

# Release

A release tells the other machines what changed and what to do after pulling. It is a tag
`vX.Y.Z` on `main`, a `CHANGELOG.md` section and a GitHub release that links to both.

## Version

Semantic Versioning, decided by what another machine has to do after pulling:

| Part  | When                                                     | Another machine                                                 |
| ----- | -------------------------------------------------------- | --------------------------------------------------------------- |
| Patch | Tuned values, README, AGENTS.md, skills                  | Pull, restart the server                                        |
| Minor | A new Basalt commit or a new tier                        | Also stop the server and run `update_basalt.ps1 -commit <sha>`  |
| Major | The repository layout or the start command changes       | Follows the steps the notice lists                              |

The first release is `1.0.0`.

## 1. Preconditions

Stop and tell the user when one fails:

- The branch is `main`, `git status --porcelain -u` is empty, and after `git fetch` `main` equals
  `origin/main`.
- `vendor/basalt` sits on a commit of upstream's `main` whose `ci` run passed:
  `gh api "repos/jesdga95/basalt/actions/runs?head_sha=$(git -C vendor/basalt rev-parse HEAD)&status=success" --jq '[.workflow_runs[] | select(.name == "ci")] | length'`
  is at least 1.
- When `vendor/basalt` moved since the last tag, at least one Basalt row in `README.md` -> *Tiers*
  names its short commit. The other rows may keep the older commit their numbers were measured on.

## 2. Collect

- The last tag: `git describe --tags --abbrev=0` (none before the first release).
- The changes: `git log --format='%h %s' <last tag>..HEAD`. Write one bullet per change a reader
  of another machine notices, never one per commit, and leave out changes nobody notices.
- Search the diff since the last tag for the machine name (`$env:COMPUTERNAME`), the local user
  name (`$env:USERNAME`), `C:\Users\` and IP addresses. A hit stops the release (`AGENTS.md` ->
  *Privacy*).

## 3. Draft and confirm

`CHANGELOG.md` follows [Common Changelog](https://common-changelog.org) and is written only here.
A missing file starts with:

```markdown
# Changelog

This changelog follows [Common Changelog](https://common-changelog.org) and this project adheres
to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).
```

The new section goes above the previous one:

```markdown
## [1.1.0] - 2026-10-25

_After pulling: stop the server and run `.\update_basalt.ps1 -commit 1a2b3c4d5e6f` in PowerShell 7. It builds the engine of that Basalt commit._

### Changed
- Move Basalt to `1a2b3c4d5e6f` ([`abc1234`](https://github.com/countzero/ai_basalt/commit/abc1234))

### Added
- Add the 32 GB VRAM / 128 GB RAM tier for Qwen3.8-Flash-Next UD-IQ4_XS ([`def5678`](https://github.com/countzero/ai_basalt/commit/def5678))
```

- The date is today's. The groups are `Changed`, `Added`, `Removed`, `Fixed`, in that order, each
  left out when empty.
- A bullet is an imperative sentence and links every commit it covers.
- The notice, one italic line under the heading, says what another machine must do beyond a
  pull and a restart, and is left out otherwise. The first release reads `_Initial release._`.
- The link definition `[1.1.0]: https://github.com/countzero/ai_basalt/releases/tag/v1.1.0` goes
  at the end of the file, above the previous one.

Show the user the version and the section, and wait. Nothing is committed before they confirm.

## 4. Publish

```powershell
git add CHANGELOG.md
git commit -m "Release vX.Y.Z"
git push
$notes = Join-Path $env:TEMP 'ai_basalt-release.md'
Set-Content -LiteralPath $notes -Value @'
- [Changelog](https://github.com/countzero/ai_basalt/blob/main/CHANGELOG.md#<anchor>)
- [Code Changes](https://github.com/countzero/ai_basalt/compare/v<previous>...vX.Y.Z)
'@
gh release create vX.Y.Z --target (git rev-parse HEAD) --title vX.Y.Z --notes-file $notes
```

- The body is the two links and nothing else: `CHANGELOG.md` already says what shipped, and a
  second account is a second place to keep correct. The first release has no previous tag and
  carries only the changelog link.
- The anchor is GitHub's slug of the heading: lowercase, brackets and periods dropped, each space
  a hyphen. `## [1.1.0] - 2026-10-25` becomes `#110---2026-10-25`.
- `--target` takes the SHA, not `main`, so the tag lands on the release commit even if `main`
  moves meanwhile.
- Publish neither a draft nor a prerelease: a draft is invisible to the other machines, and a
  prerelease is not what `/releases/latest` shows.

## 5. Verify

| Check                                     | Command                                                         |
| ----------------------------------------- | --------------------------------------------------------------- |
| Neither a draft nor a prerelease          | `gh release view vX.Y.Z --json isDraft,isPrerelease`            |
| The tag is on the release commit          | `git fetch --tags; git log -1 --format='%h %s' vX.Y.Z`          |
| It is the latest release                  | `gh release view --json tagName`                                |
| The anchor lands on the heading           | Open the changelog link                                         |
| The compare link spans the intended range | `gh api repos/countzero/ai_basalt/compare/v<previous>...vX.Y.Z` |

A wrong link is fixed with `gh release edit vX.Y.Z --notes-file <file>`, which leaves the tag and
the date alone.
