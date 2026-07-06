#!/usr/bin/env bash
# os-linux.sh — Linux backend for small-model-skills bin/ wrappers. Sourced by common.sh.
# Today's original (pre-cross-platform) behavior, extracted into sms_* functions.
# WSL2 uses this file unmodified — common.sh treats WSL2 as SMS_OS=linux.

sms_nproc(){ nproc 2>/dev/null || echo 1; }
sms_loadavg(){ awk '{print $1}' /proc/loadavg 2>/dev/null; }
sms_meminfo(){ free -h 2>/dev/null | awk '/^Mem:|^Swap:/{print}'; }
sms_swap_used_kb(){ free 2>/dev/null | awk '/^Swap:/{print $3+0}'; }
sms_top_procs_cpu(){ ps -eo pid,comm,%cpu,%mem --sort=-%cpu 2>/dev/null | tail -n +2 | head -"${1:-5}"; }
sms_top_procs_mem(){ ps -eo pid,comm,%mem,%cpu --sort=-%mem 2>/dev/null | tail -n +2 | head -"${1:-5}"; }
sms_top_cpu_pct(){ ps -eo %cpu --sort=-%cpu --no-headers 2>/dev/null | head -1; }

sms_local_links(){ ip -br link 2>/dev/null | awk '$1!="lo"{print $1, $2}'; }
sms_host_addr(){ ip -4 -br addr 2>/dev/null | awk '$1!="lo" && $3!=""{print $1, $3; exit}'; }
sms_default_gw(){ ip route show default 2>/dev/null | awk '/default/{print $3; exit}'; }
sms_default_iface(){ ip route show default 2>/dev/null | awk '/default/{print $5; exit}'; }
sms_ping(){ ping -c2 -W1 "$1" >/dev/null 2>&1; }
sms_resolve_system(){ getent hosts "$1" >/dev/null 2>&1; }

sms_failed_services(){ have systemctl && systemctl --failed --no-legend --plain 2>/dev/null | awk '{print $1}'; }
sms_recent_errors(){ have journalctl && journalctl -p err -S -1h --no-pager -q 2>/dev/null; }
sms_recent_errors_count(){ have journalctl && journalctl -p err -S -1h --no-pager -q 2>/dev/null | grep -c .; }
sms_error_sources_this_boot(){
  have journalctl && journalctl -b -p err --no-pager -q 2>/dev/null \
    | awk '{print $5}' | sed 's/\[[0-9]*\]:\?$//; s/:$//' | grep -v '^$' | sort | uniq -c | sort -rn
}

sms_df(){ df -h -x tmpfs -x devtmpfs -x squashfs -x overlay 2>/dev/null; }
sms_df_fullest(){
  df -P -x tmpfs -x devtmpfs -x squashfs -x overlay 2>/dev/null \
    | awk 'NR>1{u=$5; gsub("%","",u); if(u+0>m){m=u+0;p=$6}} END{print p}'
}
sms_du_top1(){ du -x -h -d1 "$1" 2>/dev/null; }
sms_du_summary(){ du -x -sh "$1" 2>/dev/null | cut -f1; }
