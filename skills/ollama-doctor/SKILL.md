---
name: ollama-doctor
description: Diagnose the local Ollama model stack when a local model won't load, runs slowly, or before relying on it offline. Reports whether the daemon is up, which models are installed, what's loaded, whether a model fits in VRAM or is spilling to CPU, and why inference is slow.
x-wrappers: [ollama-doctor]
---

# ollama-doctor

Use when the local model (the offline "brain") misbehaves — won't load, is slow — or to confirm it's ready before you lose network.

## Steps
1. Run `ollama-doctor`. It queries the local Ollama API (read-only) and prints daemon status, installed models + sizes, what's loaded now, GPU/VRAM, and a verdict.
2. Read the **verdict** line and act on it:
   - `DAEMON DOWN` → Ollama isn't running. Propose starting it: `ollama serve` (or `systemctl start ollama`).
   - `NO MODELS` → nothing is pulled. Propose `ollama pull <a tool-capable coder model>` while still online.
   - `CPU SPILL` → a loaded model doesn't fit VRAM and runs partly on CPU (slow). Propose a smaller model/quant or a lower `num_ctx`; see the `in_gpu%` column.
   - `HEALTHY` → it's ready; run `claude-local` to use it with these skills.
3. Report the verdict and the one proposed action. Do not start, stop, or pull anything yourself.

Read-only: it only performs GET requests against the local Ollama API and reads `nvidia-smi`.
