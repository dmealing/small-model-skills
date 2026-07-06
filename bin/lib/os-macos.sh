#!/usr/bin/env bash
# os-macos.sh — macOS (BSD) backend for small-model-skills bin/ wrappers. Sourced by common.sh.
# Same function names as os-linux.sh, native macOS primitives: sysctl/vm_stat/route/launchd/log show.

sms_nproc(){ sysctl -n hw.ncpu 2>/dev/null || echo 1; }
sms_loadavg(){ sysctl -n vm.loadavg 2>/dev/null | awk '{gsub(/[{}]/,""); print $1}'; }

sms_meminfo(){
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
  printf 'Mem:    %s total   %s used   %s free\n' "$(sms_human "${total_b:-0}")" "$(sms_human "$used_b")" "$(sms_human "$free_b")"
  swap=$(sysctl -n vm.swapusage 2>/dev/null | sed 's/^ *//')
  printf 'Swap:   %s\n' "${swap:-unknown}"
}
sms_swap_used_kb(){
  # "total = 4096.00M  used = 3040.56M  free = 1055.44M  (encrypted)" — value is two fields
  # after the "used" token ("used" "=" "3040.56M").
  sysctl -n vm.swapusage 2>/dev/null \
    | awk '{for(i=1;i<=NF;i++) if($i=="used"){v=$(i+2); gsub(/M$/,"",v); printf "%d\n", v*1024; exit}}'
}

sms_top_procs_cpu(){ ps -Aceo pid,comm,%cpu,%mem -r 2>/dev/null | tail -n +2 | head -"${1:-5}"; }
sms_top_procs_mem(){ ps -Aceo pid,comm,%mem,%cpu -m 2>/dev/null | tail -n +2 | head -"${1:-5}"; }
sms_top_cpu_pct(){ ps -Aceo %cpu -r 2>/dev/null | tail -n +2 | head -1; }

sms_local_links(){
  ifconfig -a 2>/dev/null | awk '
    /^[a-zA-Z0-9]+:/{iface=$1; sub(":","",iface); st="down"}
    /status: active/{st="up"}
    /^\t?[a-zA-Z0-9]+:/ && iface!="lo0" && iface!=""{seen[iface]=st}
    END{for (i in seen) print i, seen[i]}'
}
sms_host_addr(){
  local iface; iface=$(sms_default_iface)
  [ -n "$iface" ] && ifconfig "$iface" 2>/dev/null | awk -v i="$iface" '/inet /{print i, $2; exit}'
}
sms_default_gw(){ route -n get default 2>/dev/null | awk '/gateway:/{print $2; exit}'; }
sms_default_iface(){ route -n get default 2>/dev/null | awk '/interface:/{print $2; exit}'; }
sms_ping(){ ping -c2 -t1 "$1" >/dev/null 2>&1; }
sms_resolve_system(){ dscacheutil -q host -a name "$1" 2>/dev/null | grep -q '^ip_address:'; }

# launchd has no direct systemd-"failed units" equivalent. "Last exit status" is a signed int:
# positive = the process's own exit code (a real failure signal); negative = killed by signal
# -N. -9 (SIGKILL) and -15 (SIGTERM) are excluded — normal macOS agent teardown produces these
# for the large majority of launchd jobs on any given system (measured: 52/52 non-zero exits
# were -9 on a quiet, healthy machine), so including them is 100% noise, not signal. Other
# signals (e.g. -11 SIGSEGV, -6 SIGABRT) are real crashes and stay in.
sms_failed_services(){ launchctl list 2>/dev/null | awk 'NR>1 && $2!="0" && $2!="-" && $2!="-9" && $2!="-15"{print $3, $2}'; }
sms_recent_errors(){ log show --last 1h --style compact --predicate 'messageType == 16 OR messageType == 17' 2>/dev/null; }
sms_recent_errors_count(){ sms_recent_errors | grep -c .; }
sms_error_sources_this_boot(){
  sms_recent_errors | awk '{print $5}' | grep -v '^$' | sort | uniq -c | sort -rn
}

sms_df(){ df -h 2>/dev/null | awk 'NR==1 || !/devfs|map /'; }
sms_df_fullest(){
  df -P 2>/dev/null | awk 'NR>1 && !/devfs|map /{u=$5; gsub("%","",u); if(u+0>m){m=u+0;p=$6}} END{print p}'
}
sms_du_top1(){ du -x -h -d1 "$1" 2>/dev/null; }
sms_du_summary(){ du -x -sh "$1" 2>/dev/null | cut -f1; }
