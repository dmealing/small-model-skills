# models — getting a small model working with Claude Code (Ollama)

The skills are model-agnostic, but they need a **local model that (a) supports tool-calling and (b) has
enough context for Claude Code**. Any capable ~30B-class MoE coder model works; **`qwen3-coder` is the
tested default** — well-known, tool-capable, and fast on a consumer GPU.

## Requirements for a usable engine
- **Tool-calling** capability (`ollama show <model>` lists `tools`). The skills are useless without it.
- **Raised context.** Ollama defaults to ~4K, and even 32K is too small: Claude Code's system prompt + tool
  defs alone are ~27–30K tokens, so 32K truncates real sessions and silently degrades the model. Use
  `num_ctx 65536`. See [`../docs/tuning-local-models.md`](../docs/tuning-local-models.md#2-num_ctx).

## Recipe: qwen3-coder with a safe context
`qwen3-coder` works through Claude Code out of the box; it only needs a larger context window. Build a
Claude-Code-ready variant with the bundled Modelfile:

```bash
ollama pull qwen3-coder
ollama create qwen3-coder-cc -f qwen-coder/Modelfile   # same weights, num_ctx 65536
```

Then point the offline launcher at it:

```bash
claude-local qwen3-coder-cc      # or set LOCAL_MODEL_DEFAULT in your config
```

That's the whole setup — no template surgery, no GGUF wrangling. If you bring a *different* engine, the two
requirements above still apply.
