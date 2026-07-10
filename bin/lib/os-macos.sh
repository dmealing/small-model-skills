#!/usr/bin/env bash
# os-macos.sh — macOS (BSD) backend for small-model-skills bin/ wrappers. Sourced by common.sh.
# Same function names as os-linux.sh, native macOS primitives: sysctl/vm_stat/route/launchd/log show.

smols_nproc(){ sysctl -n hw.ncpu 2>/dev/null || echo 1; }
smols_loadavg(){ sysctl -n vm.loadavg 2>/dev/null | awk '{gsub(/[{}]/,""); print $1}'; }

smols_meminfo(){
  local pagesize total_b free_p active_p inactive_p wired_p compressed_p used_b free_b swap
  pagesize=$(sysctl -n hw.pagesize 2>/dev/null); pagesize=${pagesize:-4096}
  total_b=$(sysctl -n hw.memsize 2>/dev/null)
  # vm_stat lines are "Pages <label...>:   <count>." — the count is always the second-to-last
  # field once split on [: .]+, regardless of how many words are in <label>.
  eval "$(vm_stat 2>/dev/null | awk -F'[: .]+' '
    /Pages free/{print "free_p="$(NF-1)}
    /Pages active/{print "active_p="$(NF-1)}
    /Pages inactive/{print "inactive_p="$(NF-1)}
    /Pages wired down/{print "wired_p="$(NF-1)}
    /Pages occupied by compressor/{print "compressed_p="$(NF-1)}
  ')"
  used_b=$(( (${active_p:-0} + ${inactive_p:-0} + ${wired_p:-0} + ${compressed_p:-0}) * pagesize ))
  free_b=$(( ${free_p:-0} * pagesize ))
  printf 'Mem:    %s total   %s used   %s free\n' "$(smols_human "${total_b:-0}")" "$(smols_human "$used_b")" "$(smols_human "$free_b")"
  swap=$(sysctl -n vm.swapusage 2>/dev/null | sed 's/^ *//')
  printf 'Swap:   %s\n' "${swap:-unknown}"
}
smols_swap_used_kb(){
  # "total = 4096.00M  used = 3040.56M  free = 1055.44M  (encrypted)" — value is two fields
  # after the "used" token ("used" "=" "3040.56M").
  sysctl -n vm.swapusage 2>/dev/null \
    | awk '{for(i=1;i<=NF;i++) if($i=="used"){v=$(i+2); gsub(/M$/,"",v); printf "%d\n", v*1024; exit}}'
}

smols_top_procs_cpu(){ ps -Aceo pid,comm,%cpu,%mem -r 2>/dev/null | tail -n +2 | head -"${1:-5}"; }
smols_top_procs_mem(){ ps -Aceo pid,comm,%mem,%cpu -m 2>/dev/null | tail -n +2 | head -"${1:-5}"; }
smols_top_cpu_pct(){ ps -Aceo %cpu -r 2>/dev/null | tail -n +2 | head -1; }

smols_local_links(){
  ifconfig -a 2>/dev/null | awk '
    /^[a-zA-Z0-9]+:/{iface=$1; sub(":","",iface); st="down"}
    /status: active/{st="up"}
    /^\t?[a-zA-Z0-9]+:/ && iface!="lo0" && iface!=""{seen[iface]=st}
    END{for (i in seen) print i, seen[i]}'
}
smols_host_addr(){
  local iface; iface=$(smols_default_iface)
  [ -n "$iface" ] && ifconfig "$iface" 2>/dev/null | awk -v i="$iface" '/inet /{print i, $2; exit}'
}
smols_default_gw(){ route -n get default 2>/dev/null | awk '/gateway:/{print $2; exit}'; }
smols_default_iface(){ route -n get default 2>/dev/null | awk '/interface:/{print $2; exit}'; }
smols_ping(){ ping -c2 -t1 "$1" >/dev/null 2>&1; }
smols_resolve_system(){ dscacheutil -q host -a name "$1" 2>/dev/null | grep -q '^ip_address:'; }

# launchd has no direct systemd-"failed units" equivalent. "Last exit status" is a signed int:
# positive = the process's own exit code (a real failure signal); negative = killed by signal
# -N. -9 (SIGKILL) and -15 (SIGTERM) are excluded — normal macOS agent teardown produces these
# for the large majority of launchd jobs on any given system (measured: 52/52 non-zero exits
# were -9 on a quiet, healthy machine), so including them is 100% noise, not signal. Other
# signals (e.g. -11 SIGSEGV, -6 SIGABRT) are real crashes and stay in.
smols_failed_services(){ launchctl list 2>/dev/null | awk 'NR>1 && $2!="0" && $2!="-" && $2!="-9" && $2!="-15"{print $3, $2}'; }
smols_recent_errors(){ log show --last 1h --style compact --predicate 'messageType == 16 OR messageType == 17' 2>/dev/null; }
smols_recent_errors_count(){ smols_recent_errors | grep -c .; }
smols_error_sources_this_boot(){
  smols_recent_errors | awk '{print $5}' | grep -v '^$' | sort | uniq -c | sort -rn
}

smols_df(){ df -h 2>/dev/null | awk 'NR==1 || !/devfs|map /'; }
smols_df_fullest(){
  df -P 2>/dev/null | awk 'NR>1 && !/devfs|map /{u=$5; gsub("%","",u); if(u+0>m){m=u+0;p=$6}} END{print p}'
}
# smols_df_full_pct — the use% of the fullest real filesystem, as a bare integer. Empty if none.
smols_df_full_pct(){
  df -P 2>/dev/null | awk 'NR>1 && !/devfs|map /{u=$5; gsub("%","",u); if(u+0>m)m=u+0} END{if(m!="")print m}'
}
# Bounded (see os-linux.sh) — needs `gtimeout` (coreutils) to actually cap; degrades to uncapped otherwise.
smols_du_top1(){ smols_timeout "${SMOLS_DU_TIMEOUT:-20}" du -x -h -d1 "$1" 2>/dev/null; }
smols_du_summary(){ smols_timeout "${SMOLS_DU_HOG_TIMEOUT:-8}" du -x -sh "$1" 2>/dev/null | cut -f1; }

# --- diagnostics for ollama-doctor / freeze-forensics / runaway-hunter (macOS; degrade honestly) ---
smols_gpu_name(){ system_profiler SPDisplaysDataType 2>/dev/null | awk -F': ' '/Chipset Model/{print $2; exit}'; }
smols_gpu_vram_free(){ :; }        # Apple unified memory — no discrete free-VRAM figure; caller reports "unified"
smols_gpu_vram_total(){ :; }
smols_boot_list(){ last reboot 2>/dev/null | head -8; }
smols_prev_boot_clean(){ return 2; }   # can't determine cleanly from here — treat as unknown
smols_prev_boot_kernel_tail(){ local p; p="$(ls -t /Library/Logs/DiagnosticReports/*.panic 2>/dev/null | head -1)"
  [ -n "$p" ] && { echo "panic report: $p"; tail -n "${1:-40}" "$p" 2>/dev/null; } || echo "(no panic reports found)"; }
smols_reset_reason(){ ls -t /Library/Logs/DiagnosticReports/*.panic 2>/dev/null | head -1 | sed 's/^/last panic report: /'; }
smols_mce_summary(){ echo "(n/a on macOS — no rasdaemon; see panic reports)"; }
smols_watchdog_status(){ echo "modules=n/a device=n/a systemd_runtime=n/a armed=n/a (macOS manages its own watchdog)"; }
# emit: pid age_seconds cpu mem stat comm  (macOS etime -> seconds). comm is the trailing field and
# may contain spaces (e.g. "Google Chrome") — consumers must read it as $6..NF, not just $6.
smols_procs_aged(){ ps -Aceo pid,etime,pcpu,pmem,stat,comm -r 2>/dev/null | tail -n +2 | awk '
    function e2s(e,  d,p,n,s,days){ if(index(e,"-")){split(e,d,"-");days=d[1];e=d[2]}else days=0;
      n=split(e,p,":"); if(n==3)s=p[1]*3600+p[2]*60+p[3]; else if(n==2)s=p[1]*60+p[2]; else s=p[1];
      return days*86400+s }
    { comm=$6; for(i=7;i<=NF;i++) comm=comm" "$i;
      printf "%s %s %s %s %s %s\n",$1,e2s($2),$3,$4,$5,comm }'; }
