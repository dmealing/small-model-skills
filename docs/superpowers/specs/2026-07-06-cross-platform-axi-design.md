# Cross-platform support (macOS/Linux/Windows) + AXI output conventions — design

## Context

`small-model-skills` was built and tested on Linux; every `bin/` wrapper calls Linux-only
primitives directly: `nproc`, `/proc/loadavg`, `free`, GNU-flavored `ps`/`df`/`du`, `systemctl`/
`journalctl`, and `iproute2` (`ip ...`). Running `install.sh` on macOS surfaced two problems:

1. A real bug: `for d in "$SRC"/skills/*/; do cp -a "$d" "$SKILLS/"; done` flattens every skill
   into `$SKILLS/` on BSD `cp` (trailing-slash source + directory dest means "copy contents", not
   "copy the directory"), because BSD and GNU `cp` disagree on that specific case. Fixed already
   (`cp -a "$d" "$SKILLS/$(basename "$d")"`) — orthogonal to this design, called out for the record.
2. The deeper issue: even where a binary exists on macOS (`ps`, `df`, `du`), the specific GNU flags
   these wrappers use (`ps --sort=-%cpu`, `df -x tmpfs`, `du -d1`) aren't BSD-`ps`/`df`/`du` flags,
   so output silently breaks rather than erroring — worse than a missing binary.

Separately: this is a good moment to bring these wrappers in line with
[AXI](https://axi.md/) conventions (TOON output, identity header, structured help hints,
meaningful exit codes), since every wrapper is being touched anyway.

**Explicitly out of scope for this spec** (follow-on): AXI's session-hook ambient-context
integration (Claude Code/Codex/OpenCode `SessionStart` hooks). That's a materially separate
feature — different part of the system (hooks/settings.json, not `bin/`) — and gets its own spec.

## Platform decisions

| Platform | Approach |
|---|---|
| Linux | Reference implementation, unchanged behavior — becomes `lib/os-linux.sh` |
| macOS | New native implementation — `lib/os-macos.sh` (sysctl/vm_stat/launchd/`log show`) |
| Windows | **No native PowerShell port.** Documented as "run inside WSL2" — reuses the Linux backend unmodified. Driver: this is for OSS adoptability, not a personal Windows box, and shipping/maintaining untested PowerShell rewrites of every wrapper (with no way to verify them) is worse than asking Windows users to do what most Windows devs already do for serious tooling. `install.sh` detects `WSL_DISTRO_NAME`/`/proc/version` containing "microsoft" and treats it as Linux; a bare (non-WSL) Windows run prints a clear one-line message pointing at WSL2 setup instead of failing confusingly deep in some script. |

## Architecture

- `bin/lib/common.sh` detects the OS once — `SMS_OS=linux|macos` (WSL2 counts as `linux`) — and
  sources exactly one of `bin/lib/os-linux.sh` / `bin/lib/os-macos.sh`.
- Both files implement the **same function names**, OS-appropriate bodies:
  `sms_nproc`, `sms_loadavg`, `sms_meminfo`, `sms_top_procs_cpu`, `sms_top_procs_mem`,
  `sms_default_gw`, `sms_default_iface`, `sms_ping`, `sms_failed_services`, `sms_recent_errors`,
  `sms_df`, `sms_du`.
- Every `bin/*` wrapper calls these helpers instead of raw platform commands. Verdict logic and
  digest structure don't change; **SKILL.md files don't change at all** — the OS split stays
  entirely below the model-facing layer (per the project's existing "scripts do the work"
  principle).
- Within each OS file, shallow flag differences are resolved directly (no cross-file fallback
  chain) — each file stays self-contained and independently readable/testable, matching the
  project's "small, well-bounded units" preference.

### macOS backend specifics

| Function | Linux (existing) | macOS (new) |
|---|---|---|
| `sms_nproc` | `nproc` | `sysctl -n hw.ncpu` |
| `sms_loadavg` | `/proc/loadavg` | `sysctl -n vm.loadavg` (strip braces) |
| `sms_meminfo` | `free -h` | `vm_stat` + `sysctl hw.memsize`, normalized to the same Mem/Swap digest shape |
| `sms_top_procs_cpu/mem` | `ps -eo ... --sort=-%cpu` | `ps -eo pid,comm,%cpu,%mem -r` / `-m` (BSD sort flags) |
| `sms_default_gw/iface` | `ip route show default` | `route -n get default` (parse `gateway`/`interface`) |
| `sms_ping` | `ping -c2 -W1` | `ping -c2 -t1` (BSD `ping`'s per-packet timeout flag differs) |
| `sms_failed_services` (`log-triage`) | `systemctl --failed` | `launchctl list \| awk '$2!=0{print $3, $2}'` (nonzero last-exit-status jobs — closest launchd equivalent, not identical semantics, noted in the digest) |
| `sms_recent_errors` (`log-triage`) | `journalctl -p err -S -1h` | `log show --last 1h --predicate 'messageType == 16 OR messageType == 17'` (error/fault levels) |
| `sms_df/sms_du` | `-x tmpfs ...` / `-d1` | macOS `df` has no `-x`; filter excluded fstypes with `awk` post-filter instead. `du -d 1` works identically on macOS's BSD `du` (verified on this machine) — no change needed there |

`sensors`/`nvidia-smi` in `sys-diag` stay behind the existing `have()` check on both platforms —
no thermal read exists on Apple Silicon without `powermetrics` (needs sudo), so macOS prints
`(thermal read requires 'sudo powermetrics' — not run automatically)` rather than silently
omitting the section.

## AXI output conventions

Applied to every `bin/*` wrapper in the same pass (they're already being touched):

1. **Identity header** — first two lines of every wrapper's output:
   ```
   bin: ~/.local/bin/sys-diag
   description: Read-only snapshot: CPU/load/memory/top processes/thermal
   ```
2. **TOON for list-shaped data** — `sys-diag`'s top-CPU/top-mem process tables and `log-triage`'s
   failed-unit list become TOON arrays instead of hand-formatted columns:
   ```
   procs_cpu[5]{pid,comm,cpu,mem}:
     4821,ollama,712,41
     ...
   ```
   Scalar sections (load, memory totals, verdict) stay as simple `key: value` lines — TOON doesn't
   buy anything over that for single key/value pairs, and it keeps the diff against current output
   small.
3. **Structured `help[]` hints** replace/augment the current prose verdict suggestions — keep the
   plain-English verdict sentence (small models need the explanation, not just a command), but add
   a `help[N]:` block with concrete runnable commands:
   ```
   verdict: HIGH LOAD — 1-min load (6.2) well above core count (8)
   help[1]: Run `ps -eo pid,comm,%cpu --sort=-%cpu | head` for the full process list
   ```
4. **Exit codes**, newly meaningful (currently unused — everything exits 0 or crashes on `set -u`):
   - `0` — diagnosis ran to completion (even if it found a problem — that's data, not tool failure)
   - `1` — the tool itself failed (couldn't gather any data at all, e.g. no permissions)
   - `2` — usage error (bad flag) — only relevant to wrappers that gain flags (none currently do)
5. **Definitive empty states** — already partially done (`"none — no failed units"`); make it
   consistent across all four diagnostic wrappers.

Not applied (doesn't fit these tools): `--fields`/`--full` truncation-expansion flags (digests are
already deliberately ~20 lines, nothing here is truncated the way a large text blob would be),
pagination/aggregate-count headers (no collections large enough to paginate), idempotent-mutation
semantics (everything is read-only by design already).

## Repo layout changes

```
bin/lib/common.sh       — OS detection (SMS_OS), sources os-linux.sh or os-macos.sh
bin/lib/os-linux.sh     — new: today's Linux-specific bodies, extracted as functions
bin/lib/os-macos.sh     — new: macOS-specific bodies
bin/sys-diag            — calls sms_* helpers instead of raw commands; adds identity header + TOON + help[]
bin/log-triage          — same
bin/net-diag            — same
bin/disk-report         — same
install.sh              — detect WSL2 (treat as linux); on bare Windows, print a clear message pointing at WSL2 setup instead of failing deep in a wrapper
docs/authoring-small-model-skills.md — short addendum: new wrappers should call sms_* helpers for OS-varying primitives, and follow the AXI conventions above (identity header, TOON for list data, help[] hints, exit codes)
README.md               — note macOS + WSL2("Windows") support alongside Linux
```

`skills/*/SKILL.md` — **unchanged**. `modules/router/` — unchanged (SNMP/router queries are already
platform-agnostic; no OS-specific behavior there).

## Testing

- Each `os-*.sh` file is independently runnable/testable (same function names, swap which file
  `common.sh` sources via `SMS_OS` override for manual testing without needing both OSes on hand).
- No CI runner for macOS exists in this repo today (per `.github/workflows`) — recommend adding a
  `macos-latest` job to run the wrappers and confirm they exit 0 (or a documented non-zero) and
  produce non-empty digests, not fixed asserted mock system state, since the mock state differs
  per-runner.
- WSL2 path gets no CI (bash-only, running Ubuntu-under-WSL2 image is real effort for good faith).
  Rely on the Linux CI job as the proxy, since WSL2 runs the exact same `os-linux.sh` unmodified —
  document this as the honest scope, not "WSL2 tested," in `SECURITY.md`/`README.md` if either
  currently over-claims platform testing.

## Open follow-on (separate spec)

AXI session-hook ambient context (Claude Code/Codex/OpenCode `SessionStart` hooks showing e.g.
network/disk health before the model does anything) — well-matched to this repo's own noted
weakness ("auto-triggering is unreliable at this size"), but scoped separately since it touches
hooks/settings.json rather than `bin/`.
