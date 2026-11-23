#!/usr/bin/env bash
# web-search test — runs bin/web-search against a stub curl (no network) and checks gateway use, the
# token path (stdin only, never argv or output), local SearXNG fallback, and the verdicts. Fake values only.
set -uo pipefail
REPO="$(cd "$(dirname "$(readlink -f "$0")")/.." && pwd)"
command -v jq >/dev/null 2>&1 || { echo "skip: jq not installed"; exit 0; }
TMP="$(mktemp -d "${DEV_SCRATCH:-${TMPDIR:-/tmp}}/web-search-test.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP/bin"
# Stub curl: logs argv and stdin, then answers per STUB_GW (gateway HTTP code) and STUB_LOCAL (ok|empty|down).
# Stub secrets runner: puts the token in the environment, then runs the command after it.
printf '#!/usr/bin/env bash\nFAKE_TOKEN=fake-run-456 exec "$@"\n' > "$TMP/bin/fake-runner"
printf '#!/usr/bin/env bash\nexit 9\n' > "$TMP/bin/dead-runner"
chmod +x "$TMP/bin/fake-runner" "$TMP/bin/dead-runner"
cat > "$TMP/bin/curl" <<'STUB'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$STUB_LOG.argv"
url="${*: -1}"
case "$url" in
  *"/v1/"*) cat >> "$STUB_LOG.stdin"
    if [ "$STUB_GW" = 200 ]; then printf 'results[1]{title,host,snippet,url}:\n  Gw hit,example.org,snip,https://example.org\n200'
    else printf '\n%s' "$STUB_GW"; fi ;;
  *"/search?"*) case "$STUB_LOCAL" in
    ok) printf '{"results":[{"title":"Local hit","url":"https://example.net","content":"local snip"}]}' ;;
    empty) printf '{"results":[]}' ;;
    *) exit 7 ;; esac ;;
esac
STUB
chmod +x "$TMP/bin/curl"
printf '' > "$TMP/config"

run(){ # run <gw-code> <local> <gateway-url> [web-search args...]; prints output, sets RC
  local gw="$1" lo="$2" url="$3"; shift 3; rm -f "$TMP/log".*
  OUT="$(env PATH="$TMP/bin:$PATH" SMOLS_CONFIG="$TMP/config" STUB_LOG="$TMP/log" STUB_GW="$gw" STUB_LOCAL="$lo" \
    WEB_SEARCH_GATEWAY_URL="$url" WEB_SEARCH_TOKEN_CMD="printf 'fake-tok-123\n'" \
    WEB_SEARCH_TOKEN_RUNNER="${RUNNER:-}" WEB_SEARCH_TOKEN_VAR=FAKE_TOKEN \
    bash "$REPO/bin/web-search" "$@" 2>&1)"; RC=$?; }
verdict(){ printf '%s\n' "$OUT" | grep '^verdict:' | awk '{print $2, $3}'; }
PASS=0; FAIL=0
check(){ if [ "$3" = "$2" ]; then echo "  ✓ $1"; PASS=$((PASS+1)); else echo "  ✗ $1 (want '$2', got '$3')"; FAIL=$((FAIL+1)); fi; }

echo "web-search"
run 200 ok https://gw.example "rust async"
check "gateway answers: OK RESULTS" "OK RESULTS/0" "$(verdict)/$RC"
check "gateway body printed" "yes" "$(grep -q 'Gw hit' <<<"$OUT" && echo yes)"
check "token sent on stdin" "yes" "$(grep -q 'Authorization: Bearer fake-tok-123' "$TMP/log.stdin" && echo yes)"
check "token never in argv" "no" "$(grep -q 'fake-tok-123' "$TMP/log.argv" && echo yes || echo no)"
check "token never in output" "no" "$(grep -q 'fake-tok-123' <<<"$OUT" && echo yes || echo no)"
check "query is URL-encoded" "yes" "$(grep -q 'q=rust%20async' "$TMP/log.argv" && echo yes)"

run 200 ok https://gw.example --brave --fresh w "x"
check "--brave hits brave/web with freshness" "yes" "$(grep -q '/v1/brave/web?q=x&max_results=8&format=toon&freshness=pw' "$TMP/log.argv" && echo yes)"
run 200 ok https://gw.example --fresh m -n 3 "x"
check "--fresh on searxng uses time_range" "yes" "$(grep -q 'searxng/search?q=x&max_results=3&format=toon&time_range=month' "$TMP/log.argv" && echo yes)"

RUNNER=fake-runner run 200 ok https://gw.example "x"
check "runner mode: OK RESULTS" "OK RESULTS/0" "$(verdict)/$RC"
check "runner mode: runner token sent on stdin" "yes" "$(grep -q 'Authorization: Bearer fake-run-456' "$TMP/log.stdin" && echo yes)"
check "runner mode: token never in argv" "no" "$(grep -q 'fake-run-456' "$TMP/log.argv" && echo yes || echo no)"
RUNNER=dead-runner run 200 ok https://gw.example "x"
check "dead runner falls back to local" "WARN FALLBACK/0" "$(verdict)/$RC"

run 502 ok https://gw.example "x"
check "gateway down, local answers: WARN FALLBACK" "WARN FALLBACK/0" "$(verdict)/$RC"
check "fallback results printed" "yes" "$(grep -q 'Local hit' <<<"$OUT" && echo yes)"
run 200 ok "" "x"
check "no gateway configured: local OK" "OK RESULTS/0" "$(verdict)/$RC"
check "no gateway configured: gateway not called" "no" "$(grep -q '/v1/' "$TMP/log.argv" && echo yes || echo no)"
run 200 empty "" "x"
check "local empty: WARN NO_RESULTS" "WARN NO_RESULTS/0" "$(verdict)/$RC"
run 502 down https://gw.example "x"
check "both down: FAIL SEARCH_DOWN exit 1" "FAIL SEARCH_DOWN/1" "$(verdict)/$RC"
run 200 ok "" --brave "x"
check "--brave without gateway: FAIL NO_GATEWAY" "FAIL NO_GATEWAY/1" "$(verdict)/$RC"
run 200 ok "" -n abc "x"
check "bad -n: usage exit 2" "2" "$RC"
run 200 ok ""
check "no query: usage exit 2" "2" "$RC"

echo "$PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
