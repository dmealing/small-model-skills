# smon — routine system monitor

`smon` turns the small-model-skills diagnostic probes into a cheap, cross-machine monitor.
Every sweep it runs each configured probe, reads its **verdict contract** line
(`verdict: <OK|WARN|FAIL> <TAG> — prose`), and alerts you only on meaningful state
transitions — never on every threshold blip.

## How it works

```
cron (e.g. every 10 min) → smon:
  for each probe: run it, read its verdict, compare to last sweep
  → FAIL:            push immediately (bypasses quiet hours)
                     FAIL ships raw prose by default (no model wait) unless SMON_ENRICH_FAIL=1
                     re-pushes every SMON_FAIL_REMIND_SWEEPS if still standing (optional)
  → WARN (sustained): push only after it persists SMON_WARN_SUSTAIN sweeps (rides out blips)
  → recovery:        push a "resolved" note (bypasses quiet hours)
  unchanged:         silent
  end of sweep:      heartbeat (so a dead/frozen host is detectable Kuma-side)
                     once-daily digest at SMON_DIGEST_HOUR (optional "all-clear" summary)
```

The deterministic core decides **whether** to alert. An optional cheap model (`SMON_BRAIN`)
only **enriches** the message — if it's down or offline, the raw verdict prose ships. FAIL
alerts ship raw by default (no model wait for critical alerts) unless `SMON_ENRICH_FAIL=1`.
Steady state (all OK) makes zero model calls.

## Design intent (why it looks like this)

Two earlier monitors on the maintainer's fleet were retired because they alerted on every
blip (sirens, modals, screen flashes) — training you to ignore them. smon is deliberately
quiet: transition-only, sustained-WARN, quiet-hours for non-critical, and no local alert
theater. See `../docs/superpowers/specs/2026-07-10-smon-system-monitor-design.md`.

## Install

Run `install.sh` from the repo root — it copies `monitor/` and symlinks `smon` onto your PATH.
Then edit the config:

```sh
./install.sh    # copies monitor/ and symlinks smon to ~/.local/bin (or $SMOLS_BINDIR)
cp monitor/monitor.conf.example ~/.config/small-model-skills/monitor.conf   # then edit
```

Host-specific config (real hostnames, LAN IPs, HA/Kuma tokens, notify targets) belongs in a
**private** config repo, deployed to each host — never committed to this public repo.

## Try it

```sh
smon --dry-run       # run a sweep, print what it WOULD alert instead of sending
smon --test-alert    # send one synthetic alert through your notify backends
smon --once sys-diag # run a single probe through the pipeline
smon                 # a real sweep (what cron runs)
```

## Cron

```
*/10 * * * * /path/to/monitor/bin/smon >/dev/null 2>&1
```

## Config

See `monitor.conf.example` for every key. The important ones:

- **Probes**: `SMON_PROBES` (which probes to run)
- **Notify**: `SMON_NOTIFY` (`ha-push kuma stdout matrix`), `SMON_FALLBACK_NOTIFY` (tried when
  primary backends fail — e.g. `matrix` for HA-down scenarios)
- **Alert policy**: `SMON_WARN_SUSTAIN`, `SMON_QUIET_START`/`END` (FAIL and recovery bypass
  quiet hours), `SMON_FAIL_REMIND_SWEEPS` (re-push standing FAIL every N sweeps; 0=never),
  `SMON_ENRICH_FAIL` (1=enrich FAIL with model; 0=ship raw for faster critical alerts)
- **Daily digest**: `SMON_DIGEST_HOUR` (hour 0-23 to push once-daily all-probe status; blank=off)
- **Enrichment**: `SMON_BRAIN` (`glm|local|none`)

Backends: `ha-push` (Home Assistant mobile push), `kuma` (Uptime Kuma heartbeat), `matrix`
(Matrix room via client-server API), `stdout`. Matrix config: `SMON_MATRIX_URL` (homeserver),
`SMON_MATRIX_ROOM` (!room:server), `SMON_MATRIX_TOKEN_CMD` (prints access token).

Probe thresholds themselves (`DISK_WARN_PCT`, `TEMP_WARN_C`, …) live in the probes' own config
(`~/.config/small-model-skills/config`); smon does not re-implement them.
