#!/usr/bin/env bash
# model-bench runner — run each model over the hard-task corpus, capture full output.
#
# Models are passed as `provider:modelid` args:
#   ollama:qwen3-coder-cc        local Ollama (no key)
#   zai:glm-5.2                  z.ai native Anthropic endpoint (key: zai.env)
#   openrouter:z-ai/glm-5.2      OpenRouter Anthropic endpoint (key: openrouter.env)
#
# Output: results.jsonl next to this script — one {model,id,secs,output} row per run.
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TASKS="$HERE/tasks-hard.json"
OUT="$HERE/results.jsonl"
CC_HOME="${CC_HOME:-$HOME/.config/small-model-skills/cc-home}"
MODELS=("${@:-}")
[ ${#MODELS[@]} -gt 0 ] || MODELS=(ollama:qwen3-coder-cc ollama:qwen3-instruct-cc openrouter:z-ai/glm-5.2)

or_key() { sed -n 's/^OPENROUTER_API_KEY=//p' "$HOME/.config/small-model-skills/openrouter.env" 2>/dev/null | head -1; }
zai_key() { sed -n 's/^ZAI_API_KEY=//p' "$HOME/.config/small-model-skills/zai.env" 2>/dev/null | head -1; }

# model_env <provider:modelid>  -> prints env assignments (no trailing newline issues; single line)
model_env() {
  local p="${1%%:*}" m="${1#*:}"
  case "$p" in
    ollama)
      printf 'ANTHROPIC_BASE_URL=http://localhost:11434 ANTHROPIC_AUTH_TOKEN=ollama ANTHROPIC_MODEL=%s ANTHROPIC_SMALL_FAST_MODEL=%s ANTHROPIC_DEFAULT_HAIKU_MODEL=%s ANTHROPIC_DEFAULT_SONNET_MODEL=%s ANTHROPIC_DEFAULT_OPUS_MODEL=%s' "$m" "$m" "$m" "$m" "$m" ;;
    zai)
      local k; k="$(zai_key)"; [ -n "$k" ] || { echo "no z.ai key" >&2; exit 1; }
      printf 'ANTHROPIC_BASE_URL=https://api.z.ai/api/anthropic ANTHROPIC_AUTH_TOKEN=%s ANTHROPIC_MODEL=%s ANTHROPIC_SMALL_FAST_MODEL=glm-4.7 ANTHROPIC_DEFAULT_HAIKU_MODEL=glm-4.7 ANTHROPIC_DEFAULT_SONNET_MODEL=%s ANTHROPIC_DEFAULT_OPUS_MODEL=%s' "$k" "$m" "$m" "$m" ;;
    openrouter)
      local k; k="$(or_key)"; [ -n "$k" ] || { echo "no OpenRouter key" >&2; exit 1; }
      printf 'ANTHROPIC_BASE_URL=https://openrouter.ai/api ANTHROPIC_AUTH_TOKEN=%s ANTHROPIC_MODEL=%s ANTHROPIC_SMALL_FAST_MODEL=z-ai/glm-4.7-flash ANTHROPIC_DEFAULT_HAIKU_MODEL=z-ai/glm-4.7-flash ANTHROPIC_DEFAULT_SONNET_MODEL=%s ANTHROPIC_DEFAULT_OPUS_MODEL=%s' "$k" "$m" "$m" "$m" ;;
    *) echo "unknown provider '$p' (use ollama:|zai:|openrouter:)" >&2; exit 1 ;;
  esac
}

mkdir -p "$HERE"
: > "$OUT"
n="$(jq length "$TASKS")"
for spec in "${MODELS[@]}"; do
  echo ">>> $spec" >&2
  # warm local models
  [ "${spec%%:*}" = "ollama" ] && eval "env $(model_env "$spec") CLAUDE_CONFIG_DIR=$CC_HOME ANTHROPIC_API_KEY= timeout 60 claude -p 'hi' </dev/null >/dev/null 2>&1" || true
  for i in $(seq 0 $((n-1))); do
    id="$(jq -r ".[$i].id" "$TASKS")"
    prompt="$(jq -r ".[$i].prompt" "$TASKS")"
    bash_ok="$(jq -r ".[$i].bash" "$TASKS")"
    tools=(); [ "$bash_ok" = "true" ] && tools=(--allowedTools Bash)
    t0="$(date +%s)"
    out="$(eval "env $(model_env "$spec") CLAUDE_CONFIG_DIR=$CC_HOME ANTHROPIC_API_KEY= CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC=1 timeout 200 claude -p \"\$prompt\" ${tools[*]} --output-format json </dev/null 2>/dev/null")"
    t1="$(date +%s)"
    res="$(printf '%s' "$out" | jq -r '.result // "(timeout/no-result)"' 2>/dev/null)"
    jq -n --arg m "$spec" --arg id "$id" --argjson secs "$((t1-t0))" --arg out "$res" \
      '{model:$m,id:$id,secs:$secs,output:$out}' >> "$OUT"
    echo "   [$spec/$id] $((t1-t0))s" >&2
  done
done
echo "DONE -> $OUT ($(jq -s length "$OUT" 2>/dev/null || wc -l < "$OUT") rows)" >&2
