#!/usr/bin/env bash
# install-model.sh — build a Claude-Code-ready Ollama model from InternScience/Agents-A1.
#
# Agents-A1's stock GGUF chat template has raise_exception guards that break Ollama's tool-call
# parser when a system message + tools are present (i.e. every Claude Code request). This strips ONLY
# the two breaking guards from the model's OWN template — preserving its native Qwen3-Coder XML tool
# format and <think> reasoning — and imports the result. See ../README.md for the why.
#
# Requires: hf (HuggingFace CLI), python3 with the 'gguf' package, ollama. ~21 GB download + ~21 GB local.
set -euo pipefail
GGUF_REPO="${GGUF_REPO:-InternScience/Agents-A1-Q4_K_M-GGUF}"
GGUF_NAME="${GGUF_NAME:-Agents-A1-Q4_K_M.gguf}"
BASE_REPO="${BASE_REPO:-InternScience/Agents-A1}"     # source of the chat template
MODEL_NAME="${MODEL_NAME:-agents-a1}"
CTX="${CTX:-32768}"
WORK="${WORK:-$PWD}"
cd "$WORK"

command -v hf >/dev/null       || { echo "need the HuggingFace 'hf' CLI (pip install huggingface_hub)"; exit 1; }
command -v ollama >/dev/null   || { echo "need ollama"; exit 1; }
python3 -c "import gguf" 2>/dev/null || pip install --user gguf

echo "[1/4] download official GGUF ($GGUF_NAME) ..."
[ -f "$GGUF_NAME" ] || hf download "$GGUF_REPO" "$GGUF_NAME" --local-dir .

echo "[2/4] fetch the model's own template + strip the two breaking guards ..."
hf download "$BASE_REPO" chat_template.jinja --local-dir . >/dev/null 2>&1 \
  || curl -fsSL "https://huggingface.co/$BASE_REPO/raw/main/chat_template.jinja" -o chat_template.jinja
sed -i "/System message must be at the beginning/d; /No user query found in messages/d" chat_template.jinja

echo "[3/4] write a patched GGUF carrying the fixed template ..."
FIXED="${GGUF_NAME%.gguf}-fixed.gguf"
python3 -m gguf.scripts.gguf_new_metadata --chat-template "$(cat chat_template.jinja)" "$GGUF_NAME" "$FIXED"

echo "[4/4] import into Ollama as '$MODEL_NAME' ..."
cat > Modelfile <<EOF
FROM ./$FIXED
PARAMETER num_ctx $CTX
PARAMETER temperature 0.85
PARAMETER top_p 0.95
PARAMETER top_k 20
PARAMETER presence_penalty 1.1
EOF
ollama create "$MODEL_NAME" -f Modelfile

echo
echo "Done. Verify tool-calling survives multi-turn before trusting it:"
echo "  ollama show $MODEL_NAME   # should list 'tools'"
echo "Use it with the skills:  claude-local $MODEL_NAME"
echo "(You can delete $GGUF_NAME and $FIXED afterward — Ollama keeps its own copy.)"
