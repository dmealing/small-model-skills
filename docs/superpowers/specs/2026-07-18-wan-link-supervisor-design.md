# wan-link-supervisor — health-scored WAN failover with a bounded local-model advisor (design/spec)

**Date:** 2026-07-18
**Status:** proposed
**Related:** [`2026-07-10-smon-system-monitor-design.md`](2026-07-10-smon-system-monitor-design.md) (smon), [`../../verdict-contract.md`](../../verdict-contract.md), `modules/router/sonicwall.sh` (GET-only vendor module)

## Goal

Fix premature WAN failback on a dual-WAN edge (primary ISP + Starlink backup on a SonicWall) and generalize it to **run on whichever link is least-bad**, without flapping. Add optional, safe, **offline-capable** intelligence: a local Ollama small model may *nudge* the policy in the safe direction only. Fold the resulting monitoring/alerting into `smon`.

Two problems the native firewall cannot solve on its own:

1. **Premature failback.** Basic failover with `preempt` returns to the primary after a short healthy window (successive-probe count × health-check interval — e.g. `3 × 5s ≈ 15s`). A flapping primary is "up" for ~15s between drops, so the firewall bounces back onto a still-sick link, breaking every NAT flow, VPN, and call twice per blip.
2. **No quality / least-bad sense.** The native probe is a single hard-reachability check per member: it detects *down*, not *degraded* (loss/latency), and it will fail over onto a backup that is itself down/degraded because "any available member" wins as last resort.

Hard constraints (from the operator):

- **Offline-first.** Any model in the failover decision path must be a **local Ollama** model — cloud is unreachable exactly when the WAN is down. Local small models are weak (this project's own bench: local qwens ≈ 26/36 vs cloud GLM 34/36; weak on tool-selection/restraint), so the design must tolerate a *usually-inert, occasionally-wrong* model.
- **Autonomy is acceptable** for this decision specifically: a WAN switch is reversible (unlike deleting files), so autonomous action is fine **provided a wrong choice can only be a preference mistake, never an outage**.
- **Don't fight the firewall.** The firewall keeps its own seconds-scale hard-failover reflex as the safety floor; software only expresses a *preference*.

## Principles (invariants every component preserves)

- **Fast path is deterministic and offline. No model, ever.** Sub-minute, outage-capable decisions (hard-down failover; forced return off a dead backup) are pure code.
- **The model is a slow-path advisor, two layers deep, clamped to the safe direction only.** It may lengthen a hold, break a near-tie, or bias toward caution. It may never shorten a hold below the deterministic floor, bypass the failback dwell, select a dead/worse link, or act in the fast path. A wrong answer costs at most "stayed on backup a little longer than necessary."
- **Preference-only actuation.** Software changes only WAN member *rank*; the firewall performs the actual move via its own preempt logic. Native hard-failover still works if all software is dead.
- **Engine public, config private** (same split as smon). Host specifics (firewall address, creds, interface mapping, targets, thresholds, model id) live only in per-host config deployed from a private repo. The public repo names no host.
- **Degrade to baseline.** Any model/advisor failure, slowness, or absence collapses cleanly to the deterministic behavior.

## Architecture — three decoupled components + smon

```
FAST (offline, deterministic, holds write creds)      SLOW (local Ollama, out-of-band, optional)
┌──────────────────────────────────────────┐         ┌───────────────────────────────────────┐
│ wan-link-supervisor        (private)       │ req →   │ wan-advisor        (engine public /     │
│ ~15s loop:                                 ├────────►│                     cfg private)         │
│  • sense: SonicOS stats + per-WAN quality  │         │ systemd timer ~2min + event trigger      │
│    probes (loss/RTT/jitter) + Starlink dish│         │ local qwen → STRICT bounded JSON opinion │
│  • score each link 0-100 (EWMA window)     │ ◄────── │ writes result.json (atomic)              │
│  • flap-damping (RFC-2439 shape) per link  │ result  └───────────────────────────────────────┘
│  • state machine → desired rank order      │              (read non-blocking, TTL; stale→neutral)
│  • actuate: PUT member rank via REST        │
│  • write status.json (for the probe)        │         MONITOR / ALERT (10 min)
└──────────────────────────────────────────┘         ┌───────────────────────────────────────┐
                                                       │ smon sweep runs wan-health PROBE (public)│
                                                       │  reads supervisor status.json →          │
                                                       │  emits verdict: OK|WARN|FAIL WAN_* — prose│
                                                       │ smon: transition alert + Kuma heartbeat  │
                                                       │  + enrich (glm online | local offline)   │
                                                       │  ← absorbs wan-failover-alert.sh          │
                                                       └───────────────────────────────────────┘
```

Rationale: smon sweeps every ~10 min and cannot be the control loop (failover is seconds). So the control loop is the standalone deterministic supervisor; smon's role is unchanged — consume a `verdict:` probe, alert on transitions, heartbeat — which is exactly how the smon spec already plans to **absorb `wan-failover-alert.sh`**. The advisor is deliberately **not** smon's `SMON_BRAIN`: smon's "model never gates" rule stays fully intact, and the (clamped) model influence lives only inside the WAN subsystem.

## Component 1 — `wan-link-supervisor` (private, fast, deterministic, offline)

A long-running local service (Python 3 stdlib), systemd **user** service, ~15s loop. Single-writer via `flock` (reuse the `9>&-` op-daemon-fd fix from `wan-failover-alert.sh`). State + IPC files under `$XDG_STATE_HOME` (`request.json`, `result.json`, `status.json`, `supervisor.json`). It holds the firewall **write** creds and vendor PUT logic — kept out of the public repo so the module's GET-only design and the no-leak rule hold by architecture.

**One-time firewall prep:** convert the backup member from `final_backup` to an ordinary rank-2 member (a final-backup member is always preempted and ignores the preempt setting, so rank steering requires it be a normal alternate). Set the native successive-healthy count to a short value (~60s) — the *dwell* now lives in software; native reactivation is just the firewall's own sensing.

**Sense — three signals, fused per link:**
1. **SonicOS statistics** (`reporting/failover-lb/statistics`, GET): authoritative hard up/down + which member carries traffic.
2. **Per-WAN quality probes:** ping N stable public targets *per WAN egress* → loss%, p90 RTT, jitter. Binding a probe to a specific egress needs vendor policy-based-routing on source address (per-WAN secondary source IPs + source-routed policies; `ping -I <src>`). **Leak guard:** if a route policy auto-disables when its interface drops, the probe silently falls onto the other WAN — so cross-check signal 1 and treat a member SonicOS reports down as 100% loss regardless of ping.
3. **Backup-native health (Starlink dish gRPC, optional):** dish status (drop rate, latency, obstruction) via a static route to the dish over the backup WAN — catches "backup about to be bad" *before* committing a failover to it.

**Score (per link, 0-100, sliding ~5-min window, recomputed each cycle):** start 100; hard-down → 0; loss penalty `min(50, loss%×5)`; latency penalty vs a per-link 1h-EWMA baseline `min(30, max(0,(p90−baseline−50ms)/10ms))` (so a healthy high-baseline backup like Starlink isn't scored "worse" than fiber); jitter `min(10, jitter/10)`; backup obstruction/drop over threshold → clamp ≤ 40. **healthy ≥ 80, usable ≥ 25, dead < 25.**

**Flap-damping (per link, RFC-2439 shape):** +1000 penalty per health-state transition; exponential decay ~15min half-life; cap ~8000; while penalty ≥ 2000 the link is *suppressed* (score clamped to 25 — still selectable over a dead peer; suppression must never force traffic onto a corpse); reuse below 1000. Max hold ≈ 45-60 min.

**State machine** (`ON_PRIMARY`, `ON_BACKUP`, `BOTH_BAD_HOLD`; deterministic floors that the advisor can only tighten):

| Transition | Deterministic condition |
|---|---|
| PRIMARY → BACKUP (hard) | primary hard-down AND backup usable → immediately. If backup unusable → `BOTH_BAD_HOLD` (stay, alert, no churn) |
| PRIMARY → BACKUP (soft) | backup_score − primary_score ≥ 20 for ≥ 5 min AND backup healthy |
| BACKUP → PRIMARY (failback) | primary healthy AND unsuppressed AND both hold continuously ≥ `dwell` (baseline 10 min) → switch. Primary is the tie-break preference here |
| BACKUP → PRIMARY (forced) | backup hard-down AND primary usable → immediately (least-bad beats dead; ignores dwell/damping) |
| BOTH_BAD_HOLD → * | first link usable-and-better-by-margin for ≥ 2 min wins |

**Actuate — rank steering:** express only a preferred order via `PUT` on the LB group (swap member ranks); `preempt` stays enabled so the firewall performs the move (~15-60s). Idempotent: GET group → compare desired order → write only on change → commit → GET verify → log. Hard cap ≤ 6 rank changes/hour. Writes gated ≥ 5 min apart. Full SonicOS write flow: auth → (start-management → config-mode) → PUT → review `config/pending` → commit → logout.

**Emit:** `status.json` each cycle (per-link score/state, active member, current dwell, flap penalties, advisor-applied multiplier/prefer, last write) — consumed by the `wan-health` probe.

## Component 2 — `wan-advisor` (local model, out-of-band, optional, off by default)

A local Ollama call driven by a systemd **timer** (~2 min) plus an event-trigger file the supervisor `touch`es when it enters a flapping/ambiguous state (fresh judgment during a storm without waiting for the tick). It reads the supervisor's `request.json`, runs a local model at `temp 0`, JSON-only, `smols_timeout ~45s`, and writes `result.json` atomically. **The supervisor never calls it inline and never blocks on it.**

**Request (deterministic inputs the supervisor pre-computes):** active member + state; current deterministic dwell and the clamp envelope; per-link score + downsampled 30/60-min history; flap events (1h/6h) + per-link penalty; backup dish metrics + short trend when available.

**Response (strict JSON, validated not trusted):**
```json
{ "hold_multiplier": 1.0, "prefer": "none", "confidence": 0.0, "reason": "<=140 chars" }
```
- `hold_multiplier` ∈ **[1.0, 3.0]** — multiplies the deterministic dwell. **Floor 1.0: lengthen only.**
- `prefer` ∈ {`primary`,`backup`,`none`} — honored **only** when both links usable (≥25) AND within tie margin (|Δ| < 15); a clear deterministic winner ignores it; may never name a link < 25; **cannot bypass the failback dwell**.
- `confidence` ∈ [0,1] — advice **ignored entirely below 0.5** (act only when confident, and even then only safe-direction).
- `reason` — surfaced in smon alert/digest; never parsed for control.

**Guardrails (deterministic wrapper in the supervisor):** clamp `hold_multiplier` to range; malformed/unparseable → neutral `(1.0,none)`; `prefer` filtered by usable+tie+not-dead+not-bypass-dwell; confidence gate; `result.json` TTL ~10 min (stale → neutral); the ≤6 writes/hour cap applies regardless of advice. Timeout/kill (rc 124/137/143) → neutral.

**Degradation:** advisor disabled / Ollama down / slow / stale → supervisor reads neutral default → behavior is *identical* to the deterministic system. Disable is one line (`systemctl --user disable --now wan-advisor.timer`); the supervisor never notices.

**Decision scope (what the model may influence):** failback-dwell **lengthening** (recognize a flapping storm → hold longer), **near-tie tiebreak** (both mediocre → pick within margin), **caution-bias pre-emption** (a degradation trend → raise a link's effective hold / bias prefer toward the stable link). **Out of scope for the model:** any seconds-scale switch, forced return off a dead link, and **threshold auto-tuning** — the advisor may only *emit a suggested threshold change as text* into the smon daily digest for human review; nothing auto-applies.

## Component 3 — `wan-health` probe (public engine, GET-only) + smon integration

A new public probe following `smols_*` + verdict conventions. It reads the supervisor's `status.json` (and can enrich read-only via the existing GET-only `modules/router/sonicwall.sh`) and emits one verdict line:

`verdict: <OK|WARN|FAIL> <TAG> — <prose>` with tags (priority-ordered, first match wins — the
authoritative decision tree is the comment atop `bin/wan-health`):
- `OK WAN_PRIMARY` — on primary, the active link healthy (normal steady state).
- `OK WAN_BACKUP` — on backup, healthy (failover working as intended); prose says why.
- `WARN WAN_DEGRADED` — the active link is degraded (score <80 or suppressed), the supervisor could not sense
  the firewall this cycle (`.degraded`), or the active member isn't a recognized link (data anomaly).
- `WARN WAN_FLAP_SUPPRESSED` — a link is flap-suppressed (holding on backup by design).
- `FAIL WAN_BOTH_DEGRADED` — both links unusable / `BOTH_BAD_HOLD`.
- `FAIL WAN_PROBE_FAILED` — supervisor status missing/unreadable/stale, or `jq` not installed
  (control-plane blind — itself alert-worthy).

smon consumes it on the normal ~10-min sweep: transition-based alerting (FAIL immediate, WARN sustained, recovery notes, quiet hours), Kuma heartbeat, and enrichment (`glm` online, `local` offline). This **absorbs `wan-failover-alert.sh`**: its email → smon `ha-push`; its voice announce → an HA script called by an `ha-script` backend; its state detection → the probe's verdict transitions (smon dedupes to one alert per real transition — strictly better than the current 1-minute cron, which under-counts sub-minute flaps).

## Native companion change (do first, independently valuable)

Before/independent of building the supervisor, a one-session reversible firewall config change already removes the worst of the premature failback: raise the successive-healthy count to a ~5-minute dwell and harden the probe (add an alternate target + "either responds" condition so a single-responder outage can't strand traffic on the backup for the whole dwell). Snapshot the LB group to JSON first for rollback. This is Phase 0; the supervisor later supersedes it by moving the dwell into software and reverting the native count to ~60s. (Full procedure + exact values live in the operator's private runbook, not this public spec.)

## Engine-public / config-private mapping

- **Public** (`small-model-skills/`): the `wan-health` probe; the `wan-advisor` prompt + strict-JSON validator (generic "given these numbers, return bounded JSON"); this spec. Names no host.
- **Private / local**: the **writing** `wan-link-supervisor` (write creds + vendor PUT logic); per-host `.conf` (firewall address + creds ref, primary/backup interface mapping, PBR probe source IPs, dish route, HA target, all thresholds, advisor model id + cadence, dwell/damping params), deployed from the private config repo exactly like smon.

## Config keys (per-host `.conf`, placeholders; safe defaults)

```sh
WAN_PRIMARY_IF="X1"; WAN_BACKUP_IF="X2"          # SonicWall WAN member names
WAN_FW_HOST="<firewall-ip>"; WAN_FW_PORT=8443
WAN_FW_CRED_CMD="…"                               # prints user:pass (kept out of the file)
WAN_PROBE_TARGETS="1.1.1.1 8.8.8.8 9.9.9.9"
WAN_PRIMARY_PROBE_SRC="<lan-ip-routed-via-primary>"
WAN_BACKUP_PROBE_SRC="<lan-ip-routed-via-backup>"
WAN_DISH_ENDPOINT=""                              # backup dish gRPC host:port (blank = skip dish signal)
WAN_DWELL_MIN=10                                  # baseline failback dwell (minutes)
WAN_SOFT_MARGIN=20; WAN_TIE_MARGIN=15            # switch / tiebreak score margins
WAN_DAMP_PENALTY=1000; WAN_DAMP_HALFLIFE_MIN=15; WAN_DAMP_SUPPRESS=2000; WAN_DAMP_REUSE=1000
WAN_MAX_WRITES_PER_HOUR=6; WAN_MIN_WRITE_GAP_MIN=5
WAN_ADVISOR=0                                     # 0=off (deterministic only), 1=on
WAN_ADVISOR_MODEL="qwen3-coder-cc"; WAN_ADVISOR_TIMEOUT=45; WAN_ADVISOR_TTL_MIN=10
WAN_ADVISOR_CONF_MIN=0.5; WAN_ADVISOR_HOLD_MAX=3.0
```

## Build order

- **Phase 0 — native firewall tune** (operator runbook, reversible): dwell up + probe hardening. Immediate relief, no code.
- **Phase A — deterministic system** (the first implementation plan): `wan-link-supervisor` (sense/score/damp/state-machine/rank-steer, no model) + `wan-health` probe + smon wiring + retire `wan-failover-alert.sh`. Shadow-run alongside the native config, then flip native dwell to ~60s once trusted. Delivers the entire failover fix and the smon consolidation on its own.
- **Phase B — advisor** (opt-in, off by default, after Phase A earns trust): `wan-advisor` timer + trigger + strict-JSON contract + the supervisor's clamp wrapper. Same shadow-run-then-consolidate pattern smon uses.

## Testing (shim-based, matching smon + the failover-dispatcher work)

- **Supervisor:** fake SonicOS stats + fake probe results drive the scorer/state-machine. Assert: hard-down → switch when backup usable; both-bad → HOLD (no switch); soft-degrade switch only past margin+time; failback only after dwell + unsuppressed; forced return off a dead backup ignores dwell; flap-damping suppress/decay/reuse; rank writes idempotent + rate-capped; never selects a link < 25 except as sole survivor.
- **Advisor clamp:** feed adversarial JSON (hold 0.2 / 99, prefer a dead link, prefer bypassing dwell, malformed, low confidence, stale file, timeout) → assert every one collapses to a safe/neutral outcome and never shortens a hold or picks a worse link.
- **Probe:** status.json fixtures → correct verdict tag/prose; stale/missing → `FAIL WAN_PROBE_FAILED`.
- **smon integration:** verdict transitions → expected alert/heartbeat behavior (reuse smon's shim harness).
- **Real end-to-end:** one shadow sweep on the host; confirm an alert + Kuma heartbeat; confirm a forced test failover recovers.

## Risks / honest caveats

- **Marginal value in the common case.** Deterministic flap-damping already handles a single blip; the advisor earns its keep only in messy multi-hour storms or both-mediocre-with-a-trend. This is a small, safe enhancement, not a step-change — and it is usually inert (correct for a 26/36 model).
- **New moving parts:** PBR per-WAN probes (leak-guarded via SonicOS cross-check); the advisor timer/trigger/IPC files (neutral-default degradation). Keep both boring.
- **Longer dwell on backup** means CGNAT'd backups (e.g. Starlink) leave inbound/DDNS unreachable for the dwell — surface as a `WARN` and/or pin DDNS to the primary; operator concern, noted in the private runbook.
- **Invariants preserved:** offline-first (local model only, never in the fast path); engine-public/config-private; "preference mistakes only, never outage mistakes" (the model sits *inside* that guarantee); smon's "model never gates" (intact — smon's only model call remains cosmetic enrichment).
