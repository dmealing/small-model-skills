# The verdict contract

**Audience:** anyone consuming `bin/` wrapper output — an agent, a skill, `monitor/bin/smon`, or an
external tool. This is the stable protocol every diagnostic probe in this repo speaks. Treat it as a
versioned public spec: a probe that changes this format is a breaking change for every consumer.

**Source of truth:** the format is emitted by one helper, `smols_verdict()` in `bin/lib/common.sh`. This
document is the spec derived from that implementation — if the two ever disagree, the code wins and this
doc needs updating.

## Contents
- [1. Format](#1-format)
- [2. STATUS vocabulary](#2-status-vocabulary)
- [3. TAG grammar](#3-tag-grammar)
- [4. One line, column 0](#4-one-line-column-0)
- [5. Exit-code semantics](#5-exit-code-semantics)
- [6. Worked example](#6-worked-example)

<a name="1-format"></a>
## 1. Format

Every probe ends its run by printing exactly one line of this shape:

```
verdict: <STATUS> <TAG> — <prose>
```

- `verdict:` — a literal prefix, lowercase, followed by a single space.
- `<STATUS>` — one of the three fixed values in [§2](#2-status-vocabulary).
- `<TAG>` — a short SCREAMING_SNAKE label matching the grammar in [§3](#3-tag-grammar).
- The separator between `<TAG>` and `<prose>` is a **space, em dash, space** (` — `, U+2014) — not a
  hyphen and not a colon.
- `<prose>` — a single, human-readable sentence explaining the verdict. Keep it to one sentence; a
  consumer should never need to parse past the em dash to know what to alert on, but the prose is what a
  human (or a model with scarce context) reads to understand *why*.

<a name="2-status-vocabulary"></a>
## 2. STATUS vocabulary

Exactly three values, no others:

| STATUS | Meaning |
|---|---|
| `OK`   | Nominal / healthy. Nothing to do. |
| `WARN` | A real problem was found that warrants attention but isn't an emergency. |
| `FAIL` | Either a critical state, **or** the probe itself could not run (e.g. tag `PROBE_FAILED`). Both cases mean "look now" — a broken probe is lost visibility, which for a monitor is itself alert-worthy. |

`FAIL` deliberately conflates "the thing being checked is broken" with "the check couldn't run" — a
consumer must treat both as needing attention, not silently skip the latter.

<a name="3-tag-grammar"></a>
## 3. TAG grammar

```
^[A-Z][A-Z0-9_]{1,23}$
```

SCREAMING_SNAKE, starts with a letter, 2–24 characters total. TAG is the machine-keyable part of the
line — a consumer should switch on `STATUS`/`TAG`, not parse the prose. Each probe defines its own small,
fixed set of tags (see the worked example below); a consumer should not assume the tag set is closed
across all probes, only that any tag it sees matches this grammar.

<a name="4-one-line-column-0"></a>
## 4. One line, column 0

A probe run emits **exactly one** `verdict:` line, and it starts at column 0 (the very beginning of the
line — no leading whitespace, no other text on that line before it). This is what makes the contract
machine-greppable: a consumer greps `^verdict:` and gets exactly one match per run. Everything else a
probe prints (identity header, digest sections, TOON-formatted tables, help hints) is for a human or model
to read, and is not part of the contract — only the `^verdict:` line is.

<a name="5-exit-code-semantics"></a>
## 5. Exit-code semantics

The verdict `STATUS` is independent of the process exit code:

- **`0`** — the probe ran to completion, even if it found a problem. A `WARN` or `FAIL` verdict still
  exits `0` — the diagnosis succeeded; it's the *system being diagnosed* that's unhealthy, not the probe.
- **`1`** — the probe tool itself failed to gather data (e.g. a required binary is missing, or it can't
  read the data it needs). This is reported via a `FAIL` verdict with a tag like `PROBE_FAILED`, and the
  probe also exits non-zero.
- **`124` / `137` / `143`** — the probe was killed by a wall-clock timeout before it could finish (124 from GNU/coreutils
  `timeout`; 137 = 128+SIGKILL; 143 = 128+SIGTERM, e.g. BusyBox `timeout`). No `verdict:` line is printed by the
  probe itself in this case — a consumer that wraps probes with its own timeout (as `monitor/bin/smon`
  does) should treat these kill codes as a **synthetic `FAIL`** on the consumer side, since a probe that
  never returns is exactly the "lost visibility" case §2 describes.

<a name="6-worked-example"></a>
## 6. Worked example

`sys-diag` (system load/memory/thermal probe) emits tags including `CPU_HOG`, `HIGH_LOAD`,
`MEMORY_PRESSURE`, `THERMAL`, `NOMINAL`, and `PROBE_FAILED`. A concrete sample line:

```
verdict: WARN CPU_HOG — one process is using ~104% of a core (see top CPU processes).
```

Reading it against the spec above: `STATUS` is `WARN` (a real problem, not an emergency), `TAG` is
`CPU_HOG` (matches the grammar, 7 chars), and the prose is a single sentence explaining what to look at.
The exit code for this run is `0` — the probe successfully diagnosed a problem; it did not fail to run.
