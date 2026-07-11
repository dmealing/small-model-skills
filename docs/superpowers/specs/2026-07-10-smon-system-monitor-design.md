# smon — cross-machine system monitor (design/spec)

**Date:** 2026-07-10
**Status:** shipped (v1 + capabilities from roadmap)

**Capabilities added beyond spec** (2026-07-10, commit 12250ba / 97ac81e):
- FAIL re-alert (`SMON_FAIL_REMIND_SWEEPS`): re-push standing FAIL every N sweeps
- Daily digest (`SMON_DIGEST_HOUR`): once-daily all-probe status summary
- Don't-enrich-FAIL (`SMON_ENRICH_FAIL=0` default): ship FAIL raw, no model wait
- Fallback notify (`SMON_FALLBACK_NOTIFY`) + Matrix backend when primary fails
- install.sh now actually installs monitor/ and symlinks smon onto PATH

## Goal

A routine, cheap, cross-machine system monitor built on the small-model-skills diagnostic
probes. It runs each host's probes on a schedule, reads their **verdict contract** lines
(`verdict: <OK|WARN|FAIL> <TAG> — prose`, shipped in PR #9), alerts the user on meaningful
state transitions, and heartbeats so a dead/frozen host is itself detectable. Replaces two
abandoned monitors (`resource-monitor`, `system-alert-ai`) that died of alert-theater fatigue.

## Architecture — hybrid (deterministic core, model as garnish)

```
cron (every 10 min) → smon sweep:
  for each configured probe:
    run probe, grep '^verdict:' → (status, tag, prose)
    compare to last sweep's saved state
    decide per alert policy
  on an alert-worthy transition:
    [optional] GLM enrichment (≤2 sentences, 60s, temp 0; failure → raw prose)
    → HA mobile push
  always at sweep end:
    → Uptime Kuma push heartbeat
```

The deterministic core decides **whether** to alert. The model only **enriches** the message
and never gates: if the model is down/offline/slow, the raw verdict prose ships. Steady state
(everything OK) makes **zero** model calls.

## Repo split — engine public, config private

- **Public** — `small-model-skills/monitor/` (the engine, `bin/smon`): probe loop, verdict
  parsing, transition/dedupe state, alert policy, pluggable notify backends, GLM enrichment.
  Zero host specifics. Follows the repo's `smols_*` conventions. `smon` is an orchestrator, not
  a probe, so it emits no verdict of its own — it uses exit codes + logs.
- **Private** — a new private config repo (e.g. `<host>-monitor-config`): per-host `<hostname>.conf`
  (which probes, threshold overrides, HA token ref, notify target, Kuma push URL, quiet hours)
  + `deploy.sh` (rsync the right conf to each host). Hostnames / LAN IPs / tokens live
  **only** here — the no-leak rule satisfied by architecture, not vigilance. The public engine
  never names the private repo and never submodules it.

## Configuration

`smon` reads `~/.config/small-model-skills/monitor.conf` on each host (deployed from the private
repo). Keys (all optional with safe defaults):

```sh
SMON_PROBES="sys-diag disk-report log-triage runaway-hunter"  # which probes this host runs
SMON_BRAIN="glm"            # glm | local | none  — enrichment engine (none = raw prose only)
SMON_NOTIFY="ha-push"       # space-separated backends: ha-push kuma stdout matrix
SMON_FALLBACK_NOTIFY="matrix"  # (added) backends tried when primary fails (e.g. HA down)
SMON_HA_URL="http://<ha-host>:8123"
SMON_HA_TOKEN_CMD="…"       # command that prints the HA token (kept out of the file)
SMON_HA_TARGET="notify.mobile_app_<your_device>"
SMON_MATRIX_URL="http://<matrix-host>:8008"      # (added) homeserver for matrix backend
SMON_MATRIX_ROOM="!abc123:example.org"           # (added) room id
SMON_MATRIX_TOKEN_CMD="…"                        # (added) prints access token
SMON_KUMA_PUSH_URL="http://<kuma-host>:3001/api/push/<token>"
SMON_QUIET_START=23         # suppress non-FAIL push in this window (FAIL always goes)
SMON_QUIET_END=7
SMON_WARN_SUSTAIN=2         # WARN must persist this many sweeps before it pushes
SMON_FAIL_REMIND_SWEEPS=0   # (added) re-push standing FAIL every N sweeps (0=never)
SMON_ENRICH_FAIL=0          # (added) 1=enrich FAIL; 0=ship raw (faster critical alerts)
SMON_DIGEST_HOUR=           # (added) hour 0-23 for once-daily status digest (blank=off)
SMON_STATE_DIR="$HOME/.local/state/smon"
```

Threshold values themselves (DISK_WARN_PCT, TEMP_WARN_C, …) are the probes' own config keys,
already in `~/.config/small-model-skills/config` — smon does not re-implement them.

## Alert policy (the anti-fatigue core)

The last two monitors died because they alerted on every threshold blip. smon keys on the
transition of `<status,tag>` per probe:

- **→ FAIL**: push immediately (bypasses quiet hours).
- **→ WARN**: hold. Push only if the *same* WARN tag persists for `SMON_WARN_SUSTAIN` (default 2)
  consecutive sweeps — rides out momentary spikes. A WARN deferred by quiet hours stays unalerted
  and retries on a later sweep, with its count pinned at the sustain threshold so it fires
  immediately once out of quiet hours.
- **Recovery** (a state we previously alerted on returns to OK): push a short "resolved" note
  (bypasses quiet hours — closes a known-open loop rather than adding surprise noise).
- **Unchanged** from last sweep: silent.
- **Missing/broken probe**: synthesizes FAIL PROBE_MISSING and alerts (a broken probe is lost
  visibility, alert-worthy itself).
- Quiet hours defer only sustained WARNs; FAIL and recovery always deliver.

State per probe in `$SMON_STATE_DIR/<probe>.state`: `status tag pending_since sweep_count
alerted`. Single-instance via `flock` on a lock file (pattern from `wan-failover-alert.sh`).

## Enrichment (GLM, on transition only)

On an alert-worthy transition, smon feeds the probe's full digest + verdict to the cheap GLM
(z.ai endpoint, same key path as the gate/`claude-local`) asking for ≤2 sentences: what it means
+ the first thing to check. 60s timeout, temp 0. Any failure → ship the raw verdict prose.
**As shipped:** FAIL alerts skip enrichment by default (`SMON_ENRICH_FAIL=0`) — critical alerts
ship raw prose immediately instead of waiting up to 60s on the model. WARN is still enriched.
Only fires on the minority of sweeps with a transition, so cost ≈ zero.

## Delivery

- **HA mobile push** → POST `/api/services/notify/<target>` with `HA_TOKEN`. Title
  `⚠️ <host>: <TAG>`, body = enriched prose. Target default `notify.mobile_app_<your_device>`.
- **Matrix** (added) → PUT to Matrix client-server API (`/_matrix/client/v3/rooms/<room>/send/m.room.message/<txn>`)
  with `SMON_MATRIX_TOKEN`. A good fallback backend — rides different infra than HA.
- **Fallback notify** (added) → when a primary `ha-push` transport fails (e.g. HA down — the
  very infra smon monitors), try `SMON_FALLBACK_NOTIFY` backends so alerts still get out.
- **Uptime Kuma heartbeat** → `curl` the host's push-monitor URL every sweep. A *missing*
  heartbeat (Kuma-side) is how a frozen/dead host is detected — the blind spot per-host cron
  can't cover. A push monitor is created in the Uptime Kuma instance per host.

## Migration (deferred — not this build)

V1 **shadow-runs** alongside the existing crons; it does not disable or modify
`disk-space-monitor` / `wan-failover-alert.sh` / `health-check-cron` yet. After a week of trust,
a follow-up consolidates them (drop disk-space-monitor's auto-delete, fold health-check into a
daily smon digest, etc.). Out of scope here.

## Testing

Shim-based (same technique as the failover dispatcher + verdict contract work):

1. Fake probe emitting scriptable verdicts + fake `notify`/`curl`. Assert:
   no-transition → silent; →FAIL → push; WARN once → silent; WARN twice → push;
   recovery → push; model-down → raw prose ships; quiet-hours → WARN deferred (not FAIL/recovery);
   WARN tag-change alerts; missing probe → FAIL PROBE_MISSING.
   **As shipped:** 33 test cases (was 24 at spec time, was 19 after silent-loss fixes) covering
   FAIL re-alert on/off, don't-enrich-FAIL shipping raw prose, daily digest firing once-per-day
   and staying silent at wrong hour. Test suite: `monitor/test/smon-test.sh`.
2. **Real end-to-end** on the first host: one real sweep, push one test alert to the primary phone,
   confirm a Kuma heartbeat lands.

## Validation

The public engine changes go through `/no-mistakes` (GLM chain + Opus escalation) and merge as a
PR, like the verdict contract did. The private config repo is separate and not gated.

## Build order

1. This spec (committed).
2. `monitor/smon` engine + backends (public).
3. Shim tests green.
4. Private config repo + first-host conf + deploy.sh.
5. Kuma push monitor created; HA push verified to the primary phone.
6. Live end-to-end sweep on the first host; cron wired (every 10 min); shadow-run.
7. Engine validated through /no-mistakes; merge.
