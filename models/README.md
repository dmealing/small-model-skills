# models — getting a small model working with Claude Code (Ollama)

The skills in this repo are model-agnostic, but they need a **local model that (a) supports tool-calling and
(b) actually works through Claude Code's Anthropic-format requests**. That second part is where small local
models often trip — so this directory documents the setup and ships reproducible recipes.

## Requirements for a usable engine
- **Tool-calling** capability (Ollama `ollama show <model>` lists `tools`). Agentic skills are useless without it.
- **A chat template Ollama can drive with a system message + tools present** — because Claude Code always sends
  a large system prompt plus tool definitions.
- Raised context: Ollama defaults to ~4K, too small for an agent. Use a Modelfile `PARAMETER num_ctx 65536` —
  32K truncates real sessions (Claude Code's system prompt + tool defs alone are ~27–30K tokens); see
  [`../docs/tuning-local-models.md`](../docs/tuning-local-models.md#2-num_ctx).

## The gotcha: "System message must be at the beginning"
Some models (notably Qwen3.5 / Qwen3.6-family GGUFs) ship a Jinja chat template with hard guards like:

```jinja
{%- if messages[0].role != 'system' %}{{- raise_exception('System message must be at the beginning.') }}{%- endif %}
```

Ollama auto-generates its tool-call parser by **probing the template with synthetic message sequences** — some
of which don't put a system message first — and it also injects its own tool-instruction system message. Those
guards then throw, so **no tool parser can be built and the request 400s** the moment tools + a system message
are combined (exactly what Claude Code sends). Symptom:

```
API Error: 400 ... "Unable to generate parser for this template ... Jinja Exception: System message must be at the beginning."
```

### The fix (maintainer-endorsed for this bug class)
Keep the model's **own** template and remove **only** the breaking guards (`System message must be at the
beginning`, `No user query found in messages`). They're functionally unnecessary — tool instructions come from
the `tools` parameter, not a system message — so valid inputs render identically, and you keep the model's
**native** tool format and reasoning (`<think>`) handling.

**Do NOT** graft a different model's template (e.g. qwen2.5's) as a shortcut: a single call may pass by
coincidence, but it imposes a foreign tool format (Hermes-JSON vs the model's trained XML) and drops thinking,
so **multi-turn tool loops and reasoning break silently**. Always test multi-turn (feed a tool result back),
not just one call.

## Recipes
- `agents-a1/` — [InternScience/Agents-A1](https://huggingface.co/InternScience/Agents-A1) (35B MoE, 3B active;
  agentic; thinking + tool-calling). `install-model.sh` downloads the official GGUF, strips the two breaking
  guards from its own template, and imports a Claude-Code-ready `agents-a1` model. See `agents-a1/Modelfile`.

Once created, use any engine with the skills via the offline launcher, e.g. `claude-local agents-a1`.
