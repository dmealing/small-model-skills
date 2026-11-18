#!/usr/bin/env bash
# docker-hygiene test — runs the wrapper against stub `docker` and `df` commands (no real daemon):
# a broken daemon (I/O errors) must never read as CLEAN, buildx cache must be found when `system df`
# fails, a nearly full host disk must FAIL, and a healthy empty daemon is CLEAN.
set -uo pipefail
REPO="$(cd "$(dirname "$(readlink -f "$0")")/.." && pwd)"
TMP="$(mktemp -d "${DEV_SCRATCH:-${TMPDIR:-/tmp}}/docker-hygiene-test.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP/bin"

IOERR='Error response from daemon: rpc error: code = Unknown desc = blob sha256:abc: input/output error'
cat > "$TMP/bin/docker" <<EOF
#!/usr/bin/env bash
# stub docker: behaviour picked by \$SCENARIO (healthy-clean | ioerr | bigcache)
case "\$1 \${2:-}" in
  "info "*)        [ "\${2:-}" = "-f" ] && echo /var/lib/docker; exit 0 ;;
  "system df")
    case "\$SCENARIO" in
      ioerr) echo "$IOERR" >&2; exit 1 ;;
      bigcache) printf 'Images|33.41GB|26.6GB (79%%)\nContainers|311kB|0B (0%%)\nLocal Volumes|75.5GB|74.3GB (98%%)\nBuild Cache|179.3GB|179.3GB\n' ;;
      *) printf 'Images|3.3GB|0B (0%%)\nContainers|311kB|0B (0%%)\nLocal Volumes|32GB|0B (0%%)\nBuild Cache|0B|0B\n' ;;
    esac ;;
  "buildx du")     printf 'ID\tRECLAIMABLE\tSIZE\nabc\ttrue\t179.3GB\nReclaimable:\t179.3GB\nTotal:\t\t179.3GB\n' ;;
  "images "*)      [ "\$SCENARIO" = ioerr ] && { echo "$IOERR" >&2; exit 1; }; exit 0 ;;
  "volume ls")     exit 0 ;;
  "ps "*)          exit 0 ;;
  *)               exit 0 ;;
esac
EOF
cat > "$TMP/bin/df" <<'EOF'
#!/usr/bin/env bash
# stub df: $HOST_AVAIL_K free, $HOST_PCT used
printf 'Filesystem 1024-blocks Used Available Capacity Mounted\n/dev/x 970000000 1 %s %s%% /\n' "$HOST_AVAIL_K" "$HOST_PCT"
EOF
chmod +x "$TMP/bin/docker" "$TMP/bin/df"

run(){ SCENARIO="$1" HOST_AVAIL_K="$2" HOST_PCT="$3" PATH="$TMP/bin:$PATH" SMOLS_OS=linux \
  SMOLS_CONFIG=/dev/null SMOLS_DOCKER_RAW="" "$REPO/bin/docker-hygiene" 2>&1; }
PASS=0; FAIL=0
expect(){ # desc, output, extended regex that must match
  if printf '%s\n' "$2" | grep -Eq "$3"; then echo "  ✓ $1"; PASS=$((PASS+1)); else echo "  ✗ $1 (no match: $3)"; FAIL=$((FAIL+1)); fi
}
refute(){ # desc, output, extended regex that must NOT match
  if printf '%s\n' "$2" | grep -Eq "$3"; then echo "  ✗ $1 (matched: $3)"; FAIL=$((FAIL+1)); else echo "  ✓ $1"; PASS=$((PASS+1)); fi
}

echo "docker-hygiene"
out="$(run ioerr 5800000 99)"
refute "broken daemon is never CLEAN" "$out" 'verdict: OK CLEAN'
expect "system df failure is reported" "$out" 'docker system df +FAILED — .*input/output error'
expect "build cache found via buildx when system df fails" "$out" '179\.3GB build cache'
expect "nearly full host disk FAILs" "$out" 'verdict: FAIL HOST_DISK_LOW'
expect "I/O error hint says free host space first" "$out" 'Free a few GB on the host first'
expect "failed checks are listed as incomplete" "$out" 'Could not check: .*images'

out="$(run bigcache 200000000 20)"
expect "big build cache is RECLAIMABLE" "$out" 'verdict: WARN RECLAIMABLE .*179\.3GB build cache'
expect "unused images are reported" "$out" '26\.6GB unused images'
expect "buildx prune hint" "$out" "docker buildx prune -af"

out="$(run healthy-clean 200000000 20)"
expect "healthy empty daemon is CLEAN" "$out" 'verdict: OK CLEAN'
refute "no incomplete note when every check ran" "$out" 'Could not check'

echo "$PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
