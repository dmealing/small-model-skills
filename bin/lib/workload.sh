#!/usr/bin/env bash
# workload.sh — tell EXPECTED heavy work (builds, test runs, CI jobs the host is meant to run) from
# unexpected load, for sys-diag. Sourced after common.sh; read-only. Off unless WORKLOAD_ROOTS, WORKLOAD_REGEX
# or WORKLOAD_DAEMON_REGEX is set, so a host with no workload config behaves exactly as before.
#
# A process is EXPECTED when it, or any ancestor, runs under a WORKLOAD_ROOTS directory (its cwd) or has a
# command line matching WORKLOAD_REGEX — so a compiler or test JVM spawned by an expected job inherits it.
# An expected heavy process is ORPHANED when nothing live owns it any more:
#   - its working directory was deleted (the checkout it ran in is gone), or
#   - WORKLOAD_OWNER_REGEX is set and no ancestor's command line matches it, or
#   - WORKLOAD_OWNER_REGEX is blank and it was re-parented to init / a systemd manager (its parent exited).
# Needs only the OS backend helpers smols_procs_snapshot / smols_proc_cwd / smols_proc_args.

# WORKLOAD_DAEMON_REGEX names build servers that detach from whatever started them on purpose (compiler or
# build daemons kept warm between builds): matching ones are expected work and are not orphans just because
# they were re-parented (a deleted working directory still makes them orphans).
smols_work_enabled(){ [ -n "$WORKLOAD_ROOTS" ] || [ -n "$WORKLOAD_REGEX" ] || [ -n "$WORKLOAD_DAEMON_REGEX" ]; }

# _smols_work_field <snapshot> <pid> <n> — field n (2=ppid, 5=comm) of <pid> in a procs snapshot.
_smols_work_field(){ printf '%s\n' "$1" | awk -v p="$2" -v n="$3" '$1==p{ if(n==5){c=$5; for(i=6;i<=NF;i++)c=c" "$i; print c} else print $n; exit }'; }

# _smols_work_self_matches <pid> — this one process is under a root or matches the regex.
_smols_work_self_matches(){
  local pid="$1" cwd r
  if [ -n "$WORKLOAD_ROOTS" ]; then
    cwd="$(smols_proc_cwd "$pid")"; cwd="${cwd% (deleted)}"
    if [ -n "$cwd" ]; then
      for r in $WORKLOAD_ROOTS; do
        r="${r%/}"; case "$cwd/" in "$r"/*) return 0 ;; esac
      done
    fi
  fi
  [ -n "$WORKLOAD_REGEX" ] && smols_proc_args "$pid" | grep -qE -- "$WORKLOAD_REGEX"
}

# _smols_work_ancestors <snapshot> <pid> — the pid's ancestors, nearest first (stops at pid 1, max 64 hops).
_smols_work_ancestors(){
  local snap="$1" p="$2" i=0
  while [ "$i" -lt 64 ]; do
    p="$(_smols_work_field "$snap" "$p" 2)"
    case "$p" in ""|0) return 0 ;; esac
    echo "$p"; [ "$p" = 1 ] && return 0
    i=$((i+1))
  done
}

# smols_work_classify — one row per heavy process: "pid,comm,cpu,mem,class" with class expected|orphan|other.
# Heavy = %cpu >= min(WORKLOAD_CPU_PCT, CPU_HOG_PCT) or %mem >= WORKLOAD_MEM_PCT. Prints nothing when off.
smols_work_classify(){
  smols_work_enabled || return 0
  local snap cpu_min heavy pid ppid comm cpu mem class daemon a anc owned pcomm cwd
  snap="$(smols_procs_snapshot)"
  cpu_min="$WORKLOAD_CPU_PCT"; [ "$CPU_HOG_PCT" -lt "$cpu_min" ] 2>/dev/null && cpu_min="$CPU_HOG_PCT"
  heavy="$(printf '%s\n' "$snap" | awk -v c="$cpu_min" -v m="$WORKLOAD_MEM_PCT" \
    'NF>=5 && ($3+0>=c || $4+0>=m){comm=$5; for(i=6;i<=NF;i++)comm=comm" "$i; gsub(/,/,"_",comm); print $1","$2","$3","$4","comm}')"
  [ -n "$heavy" ] || return 0
  while IFS=, read -r pid ppid cpu mem comm; do
    [ -n "$pid" ] || continue
    # Exited since the snapshot (no cwd and no command line left to read): skip rather than misjudge it.
    [ -z "$(smols_proc_cwd "$pid")" ] && [ -z "$(smols_proc_args "$pid")" ] && continue
    anc="$(_smols_work_ancestors "$snap" "$pid")"
    class=other; daemon=0
    [ -n "$WORKLOAD_DAEMON_REGEX" ] && smols_proc_args "$pid" | grep -qE -- "$WORKLOAD_DAEMON_REGEX" && daemon=1
    if [ "$daemon" = 1 ] || _smols_work_self_matches "$pid"; then class=expected
    else for a in $anc; do [ "$a" = 1 ] && break; _smols_work_self_matches "$a" && { class=expected; break; }; done; fi
    if [ "$class" = expected ]; then
      cwd="$(smols_proc_cwd "$pid")"
      if [ "${cwd% (deleted)}" != "$cwd" ]; then class=orphan
      elif [ "$daemon" = 1 ]; then :
      elif [ -n "$WORKLOAD_OWNER_REGEX" ]; then
        owned=0; for a in $anc; do smols_proc_args "$a" | grep -qE -- "$WORKLOAD_OWNER_REGEX" && { owned=1; break; }; done
        [ "$owned" = 1 ] || class=orphan
      else
        pcomm="$(_smols_work_field "$snap" "$ppid" 5)"
        { [ "$ppid" = 1 ] || [ "$pcomm" = systemd ]; } && class=orphan
      fi
    fi
    echo "$pid,$comm,$cpu,$mem,$class"
  done <<EOF
$heavy
EOF
}
