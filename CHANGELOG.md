# Changelog

All notable changes to this project are documented here. The format is based on
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and this project aims to follow
[Semantic Versioning](https://semver.org/).

## [Unreleased]

### Added
- Diagnostic skills: `network-triage`, `system-triage`, `disk-report`, `log-triage`.
- Offline-dev skill: `offline-dev` (`offline-prep` pre-flight cache + `offline-doctor`).
- Deterministic, read-only wrappers (`bin/`): `net-diag`, `router-status`, `sys-diag`, `disk-report`,
  `log-triage`, `offline-prep`, `offline-doctor`.
- Authoring standard `docs/authoring-small-model-skills.md`, the `audit-small-model-skills` skill, and the
  `skill-audit` metrics linter.
- Config-driven setup (`config.example` + `~/.config/small-model-skills/config`) and `install.sh`.
- Pluggable router modules (`modules/router/`) with a SonicWall (SonicOS 7) reference implementation.
- Model recipe `models/agents-a1/` — patches the Qwen3.5 template's `raise_exception` guards so
  tool-calling works through Ollama (preserving the model's native tool + reasoning format).
- Public-repo leak guard (`.githooks/` pre-commit + pre-push, plus a CI `hygiene` workflow).
- README demo GIF, rendered from real output with no screen recording (`media/build-demo.py`).
