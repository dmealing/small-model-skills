# Tuning local models for these skills

What actually moves the needle when you run these skills against a local model through Claude Code +
Ollama — measured, not guessed. All numbers below are from one real box (a 12 GB consumer GPU + 64 GB
RAM); yours will differ, but the *shape* holds. The honest headline: **model choice dominates; most
"optimizations" are small or don't apply on the path you actually run.**

## Contents
- [1. Pick a small MoE, not a dense model — this is the whole game](#1-model-choice)
- [2. num_ctx: big enough not to truncate (correctness, not speed)](#2-num_ctx)
- [3. keep-alive: avoid the cold-load tax](#3-keep-alive)
- [4. Curated skills: a small, real context trim](#4-curated-skills)
- [5. Thinking on/off: a trap — it doesn't apply through Claude Code](#5-thinking)
- [6. AXI output: why the wrappers digest instead of dump](#6-axi)

<a name="1-model-choice"></a>
## 1. Pick a small MoE, not a dense model — this is the whole game

On a VRAM-constrained box, a **Mixture-of-Experts** model (big total, few *active* params/token) beats a
dense model of similar knowledge by an order of magnitude, because only the active experts compute per
token. Same box, same prompt:

| Model | Type | Speed | 822-token answer |
|---|---|---|---|
| **Agents-A1** (35B total, ~3B active) | MoE | **47.8 tok/s** | **17 s** |
| Nemotron-Super-49B | dense | 2.7 tok/s | ~5 min |

**~18×.** A dense 49B/70B *runs* on 64 GB RAM (hybrid GPU/CPU) but is too slow for an agentic loop; the
~30B-class MoE is the sweet spot — reliable enough to trust, fast enough to beat doing it by hand.
Everything else on this page is a rounding error next to this choice.

<a name="2-num_ctx"></a>
## 2. num_ctx: big enough not to truncate (correctness, not speed)

**Claude Code's system prompt + tool/skill defs are ~27–30K tokens before you type anything.** If the
model's `num_ctx` is 32K, a real session (tool outputs, a few turns) overflows and silently truncates the
model's own instructions — it gets *dumber* mid-session. This is a correctness bug, not a speed knob.

- `num_ctx 32K` → ~3–5K headroom → truncates on any real conversation. **Avoid.**
- `num_ctx 64K` → ~35K headroom → safe. KV-cache growth is negligible next to the model weights (measured:
  same 22 GB footprint, same GPU/CPU split at 32K vs 64K). **Use this.**
- `num_ctx 262K` (a model's native max) → wasteful KV cache for no benefit here.

The `models/agents-a1/` recipe ships `num_ctx 65536` for this reason.

<a name="3-keep-alive"></a>
## 3. keep-alive: avoid the cold-load tax

Loading a 22 GB model that spills to CPU costs real seconds. Measured:

| | total |
|---|---|
| **Cold** (model evicted, must load) | ~47 s |
| **Warm** (resident) | ~5 s |

Ollama keeps a model resident for **5 min** by default, so back-to-back use is warm. If you use the skills
intermittently, extend it so you don't pay the ~45 s reload each time:

```bash
# server-side (systemd drop-in for the ollama service)
Environment="OLLAMA_KEEP_ALIVE=30m"
```

This is the single biggest *latency* lever on the real path — the cold load, not generation, dominates.

<a name="4-curated-skills"></a>
## 4. Curated skills: a small, real context trim

Small-model tool-selection degrades as the number of skills grows, so exposing only the skills that fit
the job helps. The context cost is smaller than you'd expect, though — Claude Code uses **progressive
disclosure** (only a skill's name + description load upfront; the body loads on demand). Measured base
input tokens:

| Skills exposed | Input tokens |
|---|---|
| 0 (empty) | 27,754 |
| 10 (just these skills) | 27,711 |
| 15 (＋ large frontier skills) | 29,228 |

So skill **count** barely matters (0 vs 10 ≈ identical) — but a few **verbose-description** frontier skills
(e.g. a 220-line `no-mistakes`) add ~1,500 tokens upfront. `claude-local` points `CLAUDE_CONFIG_DIR` at a
curated config home (`install.sh` builds it) that exposes **only these skills** — a ~5% context trim plus a
smaller tool surface. Opt out with `SMS_CURATED_SKILLS=0`.

**Trade-off — it relocates the whole config root.** Pointing `CLAUDE_CONFIG_DIR` at the curated home moves
Claude Code's entire config root, so your global `~/.claude` context — `CLAUDE.md` directives, custom
`agents/`, and `commands/` — does **not** load in curated mode. That is deliberate: a weak model does better
with a small, clean context than with your full frontier-model setup. Set `SMS_CURATED_SKILLS=0` to run
against the full `~/.claude` config instead.

<a name="5-thinking"></a>
## 5. Thinking on/off: a trap — it doesn't apply through Claude Code

Tempting result, with a catch. Toggling Ollama's `think` parameter on a reasoning model, via the **raw
`/api/chat` API**, is dramatic for pure narration:

| | output | time |
|---|---|---|
| think on | 1,188 tok | 25 s |
| think off | 40 tok | 0.8 s |

**But `claude-local` doesn't use that endpoint** — it goes through Ollama's Anthropic-compatible
`/v1/messages`, and on that path the model **does not emit those big hidden thinking blocks** in the first
place (a reasoning prompt returned ~409 tokens with its reasoning inline, not a 1,000-token think-dump). So
there's nothing to turn off: **the thinking penalty is a raw-API artifact and does not apply to the path
these skills actually run on.** Don't waste time chasing it here. (If you drive Ollama directly, it's real.)

<a name="6-axi"></a>
## 6. AXI output: why the wrappers digest instead of dump

Each wrapper prints a bounded [AXI](https://axi.md/) digest — an identity line, TOON tables, a **verdict**,
and `help[]` hints — rather than a raw command dump. Feeding a model the same facts two ways (raw `ps`/`free`
output vs. the digest), via the raw API:

| | input | output | time |
|---|---|---|---|
| raw dump | 523 tok | 3,702 tok | 75 s |
| **AXI digest + verdict** | **133 tok** | 2,376 tok | 48 s |

4× less input, and — the real point — the model **reasons less** because the verdict is pre-computed; it
narrates a conclusion instead of deriving one. That bounding is what keeps a small model from wandering off
into a huge, wrong answer. This is [Anthropic's own tool-writing guidance](https://www.anthropic.com/engineering/writing-tools-for-agents)
(few tools, high-signal output), applied here.

---

**Bottom line:** run a ~30B MoE (Agents-A1), give it `num_ctx 64K`, keep it warm, let the wrappers digest.
Skip the thinking rabbit hole. Model choice is 18×; everything else is single digits.
