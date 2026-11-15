#!/usr/bin/env bash
# claude-local engine test — runs bin/claude-local against a stub `claude` (prints its env) and a stub Strata
# /health server. Covers: an Ollama tag, Strata already loaded, the context cap, the low-RAM refusal (start
# script never runs), a cold start through the start script with the context override, a start that dies, and
# an answering-but-unloaded Strata (load ok, load refused, low RAM refuses the load).
# No real model, no network beyond 127.0.0.1; every process it starts is stopped on exit.
set -uo pipefail
REPO="$(cd "$(dirname "$(readlink -f "$0")")/.." && pwd)"
CL="$REPO/bin/claude-local"
if ! command -v python3 >/dev/null || ! command -v curl >/dev/null; then echo "skip: needs python3 and curl"; exit 0; fi

TMP="$(mktemp -d "${DEV_SCRATCH:-${TMPDIR:-/tmp}}/claude-local-test.XXXXXX")"
pids=()
cleanup(){ for p in ${pids[@]+"${pids[@]}"}; do kill "$p" 2>/dev/null; done; pkill -f "$TMP/stub-strata.py" 2>/dev/null; rm -rf "$TMP"; }
trap cleanup EXIT

mkdir -p "$TMP/bin"
cat > "$TMP/bin/claude" <<'EOF'
#!/usr/bin/env bash
env | grep -E '^(ANTHROPIC_[A-Z_]*MODEL|ANTHROPIC_BASE_URL|CLAUDE_CODE_EFFORT_LEVEL|CLAUDE_CODE_MAX_[A-Z_]+|CLAUDE_CODE_SUBAGENT_MODEL|CLAUDE_STREAM_IDLE_TIMEOUT_MS)=' | sort
echo "ARGS=$*"
EOF
chmod +x "$TMP/bin/claude"
# stub Strata: /health with max_context from --config's --max-context (or --ctx), loaded after --delay seconds
cat > "$TMP/stub-strata.py" <<'EOF'
import json, sys, time, http.server
a = sys.argv[1:]
port = int(a[a.index("--port") + 1]); ctx = int(a[a.index("--ctx") + 1]) if "--ctx" in a else 65536
if "--config" in a:
    args = json.load(open(a[a.index("--config") + 1]))["args"]; ctx = int(args[args.index("--max-context") + 1])
delay = float(a[a.index("--delay") + 1]) if "--delay" in a else 0; t0 = time.time()
class H(http.server.BaseHTTPRequestHandler):
    def log_message(self, *x): pass
    def do_GET(self):
        body = json.dumps({"status": "ok", "max_context": ctx, "model": "flash-test", "loaded": time.time() - t0 >= delay,
                           "service": "strata"}).encode()
        self.send_response(200); self.send_header("Content-Type", "application/json"); self.end_headers(); self.wfile.write(body)
    def do_POST(self):
        # /load fails when started with --load-fail; otherwise it succeeds and --delay still gates "loaded".
        self.send_response(500 if (self.path == "/load" and "--load-fail" in a) else 200); self.end_headers()
http.server.HTTPServer(("127.0.0.1", port), H).serve_forever()
EOF
free_port(){ python3 -c 'import socket; s=socket.socket(); s.bind(("127.0.0.1",0)); print(s.getsockname()[1])'; }
wait_up(){ for _ in $(seq 50); do curl -fs "http://127.0.0.1:$1/health" >/dev/null 2>&1 && return 0; sleep 0.1; done; return 1; }
meminfo(){ printf 'MemTotal: 134217728 kB\nMemAvailable: %s kB\nSwapFree: %s kB\n' $(($1 * 1048576)) $(($2 * 1048576)); }
meminfo 35 37 > "$TMP/meminfo-ok"; meminfo 20 37 > "$TMP/meminfo-low"; meminfo 35 10 > "$TMP/meminfo-noswap"
printf '{"exe": "x", "args": ["--kv", "int8", "--max-context", "65536"], "port": 0}' > "$TMP/shared.json"
cp "$TMP/shared.json" "$TMP/shared.orig"
: > "$TMP/config"

PASS=0; FAIL=0
check(){ # desc, pattern (grep -E), output
  if printf '%s\n' "$3" | grep -qE -- "$2"; then echo "  ✓ $1"; PASS=$((PASS+1)); else echo "  ✗ $1 (wanted /$2/)"; printf '%s\n' "$3" | sed 's/^/      /'; FAIL=$((FAIL+1)); fi
}
run(){ env PATH="$TMP/bin:$PATH" SMOLS_CONFIG="$TMP/config" SMOLS_CURATED_SKILLS=0 XDG_CACHE_HOME="$TMP/cache" \
  XDG_STATE_HOME="$TMP/state" SMOLS_MEMINFO="$TMP/meminfo-ok" CLAUDE_LOCAL_MODEL= LOCAL_MODEL_DEFAULT= "$@" 2>&1; }

echo "claude-local engines"
out="$(run "$CL" qwen3-coder-cc -p hi)"
check "ollama tag keeps the Ollama endpoint" '^ANTHROPIC_BASE_URL=http://localhost:11434$' "$out"
check "ollama tag gets effort xhigh" '^CLAUDE_CODE_EFFORT_LEVEL=xhigh$' "$out"
check "ollama tag passes the claude args" '^ARGS=--settings .*--model qwen3-coder-cc -p hi$' "$out"
check "subagents use the local model" '^ARGS=--settings \{"env":\{"CLAUDE_CODE_SUBAGENT_MODEL":"qwen3-coder-cc"\}\}' "$out"
check "the opus slot points at the local model" '^ANTHROPIC_DEFAULT_OPUS_MODEL=qwen3-coder-cc$' "$out"
out="$(run env LOCAL_CC_MAX_CONTEXT=60000 LOCAL_MAX_OUTPUT_TOKENS=64000 LOCAL_SMALL_MODEL=tiny "$CL")"
check "ollama context cap from config" '^CLAUDE_CODE_MAX_CONTEXT_TOKENS=60000$' "$out"
check "ollama output cap from config" '^CLAUDE_CODE_MAX_OUTPUT_TOKENS=64000$' "$out"
check "ollama small model from config" '^ANTHROPIC_SMALL_FAST_MODEL=tiny$' "$out"
out="$(run env LOCAL_MODEL_ALIASES="tc=thinkingcap-27b-local sw=swift15-27b-local" "$CL" sw)"
check "an alias resolves to its Ollama tag" '^ANTHROPIC_MODEL=swift15-27b-local$' "$out"
out="$(run env LOCAL_MODEL_ALIASES="tc=thinkingcap-27b-local" "$CL" tcx)"
check "a non-alias tag is left alone" '^ANTHROPIC_MODEL=tcx$' "$out"

P="$(free_port)"; python3 -I "$TMP/stub-strata.py" --port "$P" --ctx 212992 & pids+=($!); wait_up "$P"
out="$(run env STRATA_URL="http://127.0.0.1:$P" "$CL" strata)"
check "strata points Claude Code at Strata" "^ANTHROPIC_BASE_URL=http://127.0.0.1:$P\$" "$out"
check "strata uses the model Strata reports" '^ANTHROPIC_MODEL=flash-test$' "$out"
check "strata sets the Claude Code context" '^CLAUDE_CODE_MAX_CONTEXT_TOKENS=190000$' "$out"
check "strata gets effort xhigh" '^CLAUDE_CODE_EFFORT_LEVEL=xhigh$' "$out"
out="$(run env STRATA_URL="http://127.0.0.1:$P" LOCAL_MODEL_DEFAULT=flashnext "$CL" -p hi)"
check "LOCAL_MODEL_DEFAULT=flashnext selects Strata" '^ARGS=--settings .*--model flash-test -p hi$' "$out"
kill "${pids[-1]}"

P="$(free_port)"; python3 -I "$TMP/stub-strata.py" --port "$P" --ctx 65536 & pids+=($!); wait_up "$P"
out="$(run env STRATA_URL="http://127.0.0.1:$P" "$CL" strata)"
check "a small running window caps the Claude Code context" '^CLAUDE_CODE_MAX_CONTEXT_TOKENS=58982$' "$out"
kill "${pids[-1]}"

P="$(free_port)"
cat > "$TMP/start.sh" <<EOF
#!/usr/bin/env bash
echo started >> "$TMP/started"
exec python3 -I "$TMP/stub-strata.py" --port $P --delay 3 "\$@"
EOF
chmod +x "$TMP/start.sh"
out="$(run env STRATA_URL="http://127.0.0.1:$P" STRATA_START_SCRIPT="$TMP/start.sh" STRATA_CONFIG="$TMP/shared.json" \
  SMOLS_MEMINFO="$TMP/meminfo-low" "$CL" strata)"; rc=$?
check "low RAM refuses naming both numbers" 'not starting Strata \(iq2_xs\): 20 GiB RAM available \(need 24, STRATA_MEM_FLOOR_GIB\) and 37 GiB swap free \(need 12' "$out"
check "low RAM exits non-zero" '^1$' "$rc"
out="$(run env STRATA_URL="http://127.0.0.1:$P" STRATA_START_SCRIPT="$TMP/start.sh" SMOLS_MEMINFO="$TMP/meminfo-noswap" "$CL" strata)"; rc=$?
check "low swap refuses too" '10 GiB swap free \(need 12, STRATA_SWAP_FLOOR_GIB\)' "$out"
check "low swap exits non-zero" '^1$' "$rc"
check "a refusal never runs the start script" '^absent$' "$([ -e "$TMP/started" ] && echo present || echo absent)"

out="$(run env STRATA_URL="http://127.0.0.1:$P" STRATA_START_SCRIPT="$TMP/start.sh" STRATA_CONFIG="$TMP/shared.json" "$CL" strata)"
pkill -f "$TMP/stub-strata.py --port $P" 2>/dev/null
check "cold start runs the start script" 'starting Strata \(iq2_xs, context 212992\)' "$out"
check "cold start waits for loaded" 'Strata is loaded' "$out"
check "cold start launches with the 212992 window" '^CLAUDE_CODE_MAX_CONTEXT_TOKENS=190000$' "$out"
check "the shared config is untouched" '^same$' "$(cmp -s "$TMP/shared.json" "$TMP/shared.orig" && echo same || echo changed)"
check "the override config holds the new window" '"212992"' "$(cat "$TMP"/cache/small-model-skills/shared-ctx212992.json)"

printf '#!/bin/sh\necho boom; exit 3\n' > "$TMP/start-bad.sh"; chmod +x "$TMP/start-bad.sh"
out="$(run env STRATA_URL="http://127.0.0.1:$(free_port)" STRATA_START_SCRIPT="$TMP/start-bad.sh" "$CL" strata)"; rc=$?
check "a start script that dies is reported with its log" 'exited before it finished loading' "$out"
check "a dead start exits non-zero" '^1$' "$rc"

out="$(run env STRATA_URL="http://127.0.0.1:$(free_port)" "$CL" strata)"; rc=$?
check "no start script configured is a clear error" 'STRATA_START_SCRIPT is not set' "$out"

P="$(free_port)"; python3 -I "$TMP/stub-strata.py" --port "$P" --delay 2 & pids+=($!); wait_up "$P"
out="$(run env STRATA_URL="http://127.0.0.1:$P" "$CL" strata)"; rc=$?
check "an answering-but-unloaded Strata is loaded" 'the model is unloaded; loading it' "$out"
check "loading an answering Strata succeeds" 'Strata is loaded' "$out"
check "a load with enough RAM launches Claude Code" '^ANTHROPIC_BASE_URL=http://127.0.0.1:'"$P"'$' "$out"
kill "${pids[-1]}"

P="$(free_port)"; python3 -I "$TMP/stub-strata.py" --port "$P" --delay 100 --load-fail & pids+=($!); wait_up "$P"
out="$(run env STRATA_URL="http://127.0.0.1:$P" SMOLS_MEMINFO="$TMP/meminfo-low" "$CL" strata)"; rc=$?
check "low RAM refuses to load an answering Strata" 'not loading the Strata model \(iq2_xs\)' "$out"
check "a refused load exits non-zero" '^1$' "$rc"
out="$(run env STRATA_URL="http://127.0.0.1:$P" STRATA_START_TIMEOUT=10 "$CL" strata)"; rc=$?
check "a failed load request fails fast" 'refused the model load' "$out"
check "a failed load exits non-zero" '^1$' "$rc"
kill "${pids[-1]}"

P="$(free_port)"
eng(){ run env LOCAL_ENGINES="fl other" ENGINE_fl_URL="http://127.0.0.1:$P" ENGINE_fl_HEALTH="http://127.0.0.1:$P/health" \
  ENGINE_fl_MODEL=flint-test ENGINE_fl_CTX=190000 ENGINE_fl_MAX_OUT=16000 ENGINE_fl_ENV="CLAUDE_STREAM_IDLE_TIMEOUT_MS=1800000" \
  ENGINE_fl_START_TIMEOUT=20 "$@"; }
out="$(eng ENGINE_fl_START= "$CL" fl)"
check "an endpoint engine that is down with no start command is a clear error" 'ENGINE_fl_START is not set' "$out"
out="$(eng ENGINE_fl_START="echo go >> '$TMP/fl-started'; nohup python3 -I '$TMP/stub-strata.py' --port $P >/dev/null 2>&1 &" "$CL" fl)"
check "an endpoint engine runs its start command when down" '^go$' "$(cat "$TMP/fl-started" 2>/dev/null)"
check "an endpoint engine points Claude Code at its URL" "^ANTHROPIC_BASE_URL=http://127.0.0.1:$P\$" "$out"
check "an endpoint engine uses its model" '^ANTHROPIC_MODEL=flint-test$' "$out"
check "an endpoint engine sets its context" '^CLAUDE_CODE_MAX_CONTEXT_TOKENS=190000$' "$out"
check "an endpoint engine sets its output cap" '^CLAUDE_CODE_MAX_OUTPUT_TOKENS=16000$' "$out"
check "an endpoint engine passes its extra env" '^CLAUDE_STREAM_IDLE_TIMEOUT_MS=1800000$' "$out"
check "an endpoint engine gets effort xhigh" '^CLAUDE_CODE_EFFORT_LEVEL=xhigh$' "$out"
eng ENGINE_fl_START="echo again >> '$TMP/fl-started'" "$CL" fl >/dev/null 2>&1
if [ "$(cat "$TMP/fl-started" 2>/dev/null)" = go ]; then
  echo "  ✓ an endpoint engine that is up is not started again"; PASS=$((PASS+1))
else
  echo "  ✗ an endpoint engine that is up is not started again (fl-started: $(cat "$TMP/fl-started" 2>/dev/null | tr '\n' ' '))"; FAIL=$((FAIL+1))
fi
pkill -f "$TMP/stub-strata.py --port $P" 2>/dev/null

echo "$PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
