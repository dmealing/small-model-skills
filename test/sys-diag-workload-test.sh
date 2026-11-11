#!/usr/bin/env bash
# sys-diag expected-workload / memory-floor / OOM / orphan test. Runs a temp copy of bin/ with a FAKE OS
# backend (lib/os-fake.sh, selected by SMOLS_OS=fake) that serves load, memory, OOM count and a process
# table from fixtures, so the verdict is deterministic on any host, whatever it is really running.
set -uo pipefail
REPO="$(cd "$(dirname "$(readlink -f "$0")")/.." && pwd)"

TMP="$(mktemp -d /tmp/sys-diag-test.XXXXXX)"
trap 'rm -rf "$TMP"' EXIT
cp -R "$REPO/bin" "$TMP/bin"
FIX="$TMP/fix"; mkdir -p "$FIX" "$TMP/stub"
# Host tools sys-diag would otherwise read for real: stub them silent.
for t in sensors nvidia-smi; do printf '#!/bin/sh\nexit 1\n' > "$TMP/stub/$t"; chmod +x "$TMP/stub/$t"; done

cat > "$TMP/bin/lib/os-fake.sh" <<'EOF'
. "$(dirname "${BASH_SOURCE[0]}")/os-linux.sh"
smols_nproc(){ echo "${FAKE_NPROC:-24}"; }
smols_loadavg(){ echo "${FAKE_LOAD:-1.00}"; }
smols_meminfo(){ echo "Mem: fake"; }
smols_swap_used_kb(){ echo "${FAKE_SWAPUSED_KB:-0}"; }
smols_mem_avail_pct(){ echo "${FAKE_AVAIL:-60}"; }
smols_swap_free_pct(){ echo "${FAKE_SWAPFREE:-90}"; }
smols_oom_kills_recent(){ echo "${FAKE_OOMS:-0}"; }
smols_procs_snapshot(){ cat "$FAKE_FIX/procs"; }
smols_proc_cwd(){ cat "$FAKE_FIX/$1.cwd" 2>/dev/null; }
smols_proc_args(){ cat "$FAKE_FIX/$1.args" 2>/dev/null; }
smols_top_procs_cpu(){ sort -k3,3nr "$FAKE_FIX/procs" | awk '{print $1, $5, $3, $4}' | head -"${1:-5}"; }
smols_top_procs_mem(){ sort -k4,4nr "$FAKE_FIX/procs" | awk '{print $1, $5, $4, $3}' | head -"${1:-5}"; }
smols_top_cpu_pct(){ sort -k3,3nr "$FAKE_FIX/procs" | awk '{print $3; exit}'; }
EOF

# proc <pid> <ppid> <cpu> <mem> <comm> <cwd> <args> — add one process to the fixture table.
proc(){ echo "$1 $2 $3 $4 $5" >> "$FIX/procs"; printf '%s' "$6" > "$FIX/$1.cwd"; printf '%s' "$7" > "$FIX/$1.args"; }
reset_procs(){
  rm -f "$FIX"/*
  proc 1 0 0.0 0.1 systemd / "/sbin/init"
  proc 900 1 0.0 0.1 systemd / "/lib/systemd/systemd --user"
  proc 1000 900 0.1 0.1 bash /home/u "bash"
  proc 2000 1000 0.5 0.5 agent /work/a "agent-cli run"
}
# A fleet of builds/tests under the work root /work, each owned by the agent (pid 2000).
fleet(){
  reset_procs
  proc 2100 2000 226 2.0 java /work/a "java -jar gradle-worker.jar"
  proc 2101 2000 180 3.3 java /work/b "java org.example.TestRunner"
  proc 2102 2000 121 13.1 dotnet /work/c "dotnet test"
  proc 2103 2000 64 0.2 bun /work/d "bun test"
}

run(){ SMOLS_OS=fake SMOLS_CONFIG=/dev/null FAKE_FIX="$FIX" PATH="$TMP/stub:$PATH" "$TMP/bin/sys-diag" 2>/dev/null | grep '^verdict:'; }

PASS=0; FAIL=0
check(){ local desc="$1" exp="$2" act="$3"
  if printf '%s' "$act" | grep -q -- "$exp"; then echo "  ✓ $desc"; PASS=$((PASS+1))
  else echo "  ✗ $desc — expected '$exp', got: $act"; FAIL=$((FAIL+1)); fi; }

echo "=== fleet load (load 94 on 24 cores, 4 heavy builds) ==="
fleet
check "no workload config: HIGH_LOAD as before" "WARN HIGH_LOAD" "$(FAKE_LOAD=94 run)"
check "workload roots configured + healthy memory: no alert" "OK NOMINAL" "$(WORKLOAD_ROOTS=/work FAKE_LOAD=94 run)"
check "OK prose says the load is expected work" "all expected work" "$(WORKLOAD_ROOTS=/work FAKE_LOAD=94 run)"
check "regex instead of roots also excuses it" "OK NOMINAL" "$(WORKLOAD_REGEX='java|dotnet test|bun test' FAKE_LOAD=94 run)"
reset_procs
proc 2104 2000 20 14.0 java /work/e "java -Xmx16g IntegrationTests"   # memory-heavy, CPU-light
check "heavy swap without workload config: MEMORY_PRESSURE as before" "WARN MEMORY_PRESSURE — heavy swap" "$(FAKE_SWAPUSED_KB=25000000 run)"
check "heavy swap from expected work: no MEMORY_PRESSURE" "OK NOMINAL" "$(WORKLOAD_ROOTS=/work FAKE_SWAPUSED_KB=25000000 run)"
proc 2105 1000 1 12.0 browser /home/u "browser"
check "heavy swap with an unexpected memory hog: MEMORY_PRESSURE" "WARN MEMORY_PRESSURE" "$(WORKLOAD_ROOTS=/work FAKE_SWAPUSED_KB=25000000 run)"

echo "=== expected work is inherited from an ancestor ==="
fleet
proc 2200 2100 150 1.0 javac /tmp/x "javac Foo.java"   # child of a build: cwd outside /work, still expected
check "child of expected work is expected" "OK NOMINAL" "$(WORKLOAD_ROOTS=/work FAKE_LOAD=94 run)"

echo "=== an unexpected hog alongside expected work still alerts ==="
fleet
proc 3000 1000 99 0.5 miner /home/u "miner --all-cores"
check "unexpected heavy process: load not excused" "WARN HIGH_LOAD" "$(WORKLOAD_ROOTS=/work FAKE_LOAD=94 run)"
check "unexpected hog at normal load: CPU_HOG" "WARN CPU_HOG — one process is using ~99%" "$(WORKLOAD_ROOTS=/work run)"

echo "=== memory floor: always alerts, even under expected work ==="
fleet
check "available RAM under the floor" "WARN MEMORY_PRESSURE — only 3% of RAM available" "$(WORKLOAD_ROOTS=/work FAKE_LOAD=94 FAKE_AVAIL=3 run)"
check "swap free under the floor" "only 4% of swap free" "$(WORKLOAD_ROOTS=/work FAKE_LOAD=94 FAKE_SWAPFREE=4 run)"
check "no swap at all (empty) is not a breach" "OK NOMINAL" "$(WORKLOAD_ROOTS=/work FAKE_LOAD=94 FAKE_SWAPFREE='' run)"
check "floor applies with no workload config too" "WARN MEMORY_PRESSURE" "$(FAKE_AVAIL=2 run)"

echo "=== OOM kill: always alerts ==="
fleet
check "an OOM kill in the window" "WARN OOM_KILL — 2 process(es) were killed" "$(WORKLOAD_ROOTS=/work FAKE_LOAD=94 FAKE_OOMS=2 run)"
check "OOM outranks the memory floor" "WARN OOM_KILL" "$(WORKLOAD_ROOTS=/work FAKE_AVAIL=1 FAKE_OOMS=1 run)"
check "OOM alerts with no workload config" "WARN OOM_KILL" "$(FAKE_OOMS=1 run)"

echo "=== orphaned heavy work ==="
fleet
proc 2300 900 180 4.0 java /work/e "java -jar gradle-daemon.jar"   # re-parented to the systemd manager
check "expected work re-parented to systemd: ORPHANED_WORK" "WARN ORPHANED_WORK — pid 2300 (java)" "$(WORKLOAD_ROOTS=/work FAKE_LOAD=94 run)"
fleet
proc 2301 1 90 1.0 node "/work/gone (deleted)" "node build.js"
check "expected work re-parented to init: ORPHANED_WORK" "pid 2301 (node)" "$(WORKLOAD_ROOTS=/work run)"
fleet
proc 2302 2000 90 1.0 node "/work/gone (deleted)" "node build.js"
check "expected work whose checkout was deleted: ORPHANED_WORK" "pid 2302 (node)" "$(WORKLOAD_ROOTS=/work run)"
fleet
check "owner regex matches a live ancestor: no orphan" "OK NOMINAL" "$(WORKLOAD_ROOTS=/work WORKLOAD_OWNER_REGEX='agent-cli' FAKE_LOAD=94 run)"
check "owner regex matches no ancestor: ORPHANED_WORK" "WARN ORPHANED_WORK" "$(WORKLOAD_ROOTS=/work WORKLOAD_OWNER_REGEX='some-other-owner' FAKE_LOAD=94 run)"
fleet
proc 2400 900 150 4.0 java /home/u/.cache/kotlin/daemon "java -cp x.jar org.example.KotlinCompileDaemon"
check "detached build daemon matching WORKLOAD_DAEMON_REGEX: expected, not orphaned" "OK NOMINAL" "$(WORKLOAD_ROOTS=/work WORKLOAD_DAEMON_REGEX='CompileDaemon' FAKE_LOAD=94 run)"
check "same daemon unconfigured: an unexpected heavy process" "WARN HIGH_LOAD" "$(WORKLOAD_ROOTS=/work FAKE_LOAD=94 run)"
proc 2401 900 120 1.0 node "/work/gone (deleted)" "node CompileDaemon"
check "daemon whose working directory was deleted: still ORPHANED_WORK" "pid 2401 (node)" "$(WORKLOAD_ROOTS=/work WORKLOAD_DAEMON_REGEX='CompileDaemon' FAKE_LOAD=94 run)"
fleet
proc 2300 900 180 4.0 java /work/e "java -jar gradle-daemon.jar"
check "orphan check is off with no workload config" "WARN HIGH_LOAD" "$(FAKE_LOAD=94 run)"

echo
echo "RESULT: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
