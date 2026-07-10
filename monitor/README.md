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
  → WARN (sustained): push only after it persists SMON_WARN_SUSTAIN sweeps (rides out blips)
  → recovery:        push a "resolved" note (bypasses quiet hours)
  unchanged:         silent
  end of sweep:      heartbeat (so a dead/frozen host is detectable Kuma-side)
```

The deterministic core decides **whether** to alert. An optional cheap model (`SMON_BRAIN`)
only **enriches** the message — if it's down or offline, the raw verdict prose ships. Steady
state (all OK) makes zero model calls.

## Design intent (why it looks like this)

Two earlier monitors on the maintainer's fleet were retired because they alerted on every
blip (sirens, modals, screen flashes) — training you to ignore them. smon is deliberately
quiet: transition-only, sustained-WARN, quiet-hours for non-critical, and no local alert
theater. See `../docs/superpowers/specs/2026-07-10-smon-system-monitor-design.md`.

## Install

```sh
cp monitor/monitor.conf.example ~/.config/small-model-skills/monitor.conf   # then edit
ln -s "$PWD/monitor/bin/smon" ~/.local/bin/smon                             # or add monitor/bin to PATH
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

See `monitor.conf.example` for every key. The important ones: `SMON_PROBES` (which probes),
`SMON_NOTIFY` (`ha-push kuma stdout`), `SMON_BRAIN` (`glm|local|none`), `SMON_WARN_SUSTAIN`,
`SMON_QUIET_START`/`END` (FAIL and recovery bypass quiet hours; only WARNs are deferred). Probe
thresholds themselves (`DISK_WARN_PCT`, `TEMP_WARN_C`, …) live in the probes' own config
(`~/.config/small-model-skills/config`); smon does not re-implement them.
