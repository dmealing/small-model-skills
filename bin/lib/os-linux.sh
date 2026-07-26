#!/usr/bin/env bash
# os-linux.sh — Linux backend for small-model-skills bin/ wrappers. Sourced by common.sh.
# Today's original (pre-cross-platform) behavior, extracted into smols_* functions.
# WSL2 uses this file unmodified — common.sh treats WSL2 as SMOLS_OS=linux.

smols_nproc(){ nproc 2>/dev/null || echo 1; }
smols_loadavg(){ awk '{print $1}' /proc/loadavg 2>/dev/null; }
smols_meminfo(){ free -h 2>/dev/null | awk '/^Mem:|^Swap:/{print}'; }
smols_swap_used_kb(){ free 2>/dev/null | awk '/^Swap:/{print $3+0}'; }
smols_top_procs_cpu(){ ps -eo pid,comm,%cpu,%mem --sort=-%cpu 2>/dev/null | tail -n +2 | head -"${1:-5}"; }
smols_top_procs_mem(){ ps -eo pid,comm,%mem,%cpu --sort=-%mem 2>/dev/null | tail -n +2 | head -"${1:-5}"; }
smols_top_cpu_pct(){ ps -eo %cpu --sort=-%cpu --no-headers 2>/dev/null | head -1; }

smols_local_links(){ ip -br link 2>/dev/null | awk '$1!="lo"{print $1, $2}'; }
smols_host_addr(){ ip -4 -br addr 2>/dev/null | awk '$1!="lo" && $3!=""{print $1, $3; exit}'; }
smols_default_gw(){ ip route show default 2>/dev/null | awk '/default/{print $3; exit}'; }
smols_default_iface(){ ip route show default 2>/dev/null | awk '/default/{print $5; exit}'; }
smols_ping(){ ping -c2 -W1 "$1" >/dev/null 2>&1; }
smols_resolve_system(){ getent hosts "$1" >/dev/null 2>&1; }

smols_failed_services(){ have systemctl && systemctl --failed --no-legend --plain 2>/dev/null | awk '{print $1}'; }
smols_recent_errors(){ have journalctl && journalctl -p err -S -1h --no-pager -q 2>/dev/null; }
smols_recent_errors_count(){ have journalctl && journalctl -p err -S -1h --no-pager -q 2>/dev/null | grep -c .; }
smols_error_sources_this_boot(){
  have journalctl && journalctl -b -p err --no-pager -q 2>/dev/null \
    | awk '{print $5}' | sed 's/\[[0-9]*\]:\?$//; s/:$//' | grep -v '^$' | sort | uniq -c | sort -rn
}

# LOCAL capacity view only. Beyond the pseudo/overlay types, this also excludes automount
# triggers AND the network fs types (SMOLS_NET_FSTYPES) — a df that walked an unresponsive
# network share would hang the whole probe, so network mounts are handled separately by
# smols_net_mounts + disk-report's reachability pass. Excluding an absent type is a harmless
# no-op, so this stays correct on hosts with no network mounts.
_smols_df_local_x(){
  printf '%s' '-x tmpfs -x devtmpfs -x squashfs -x overlay -x autofs -x fuse.portal'
  local t; for t in ${SMOLS_NET_FSTYPES:-cifs nfs nfs4 smbfs fuse.sshfs}; do printf ' -x %s' "$t"; done
}
smols_df(){ df -h $(_smols_df_local_x) 2>/dev/null; }
smols_df_fullest(){
  df -P $(_smols_df_local_x) 2>/dev/null \
    | awk 'NR>1{u=$5; gsub("%","",u); if(u+0>m){m=u+0;p=$6}} END{print p}'
}
# smols_df_full_pct — the use% of the FULLEST real LOCAL filesystem, as a bare integer (e.g. 87). Empty if none.
smols_df_full_pct(){
  df -P $(_smols_df_local_x) 2>/dev/null \
    | awk 'NR>1{u=$5; gsub("%","",u); if(u+0>m)m=u+0} END{if(m!="")print m}'
}
# smols_net_mounts — real network mounts as "fstype<TAB>mountpoint<TAB>source", read from
# /proc/mounts, which never blocks (unlike df/stat on the mount itself). The concrete cifs/nfs
# entry is what we report; the paired autofs trigger line for the same path is skipped.
smols_net_mounts(){
  awk -v list="${SMOLS_NET_FSTYPES:-cifs nfs nfs4 smbfs fuse.sshfs}" '
    BEGIN{ n=split(list,a," "); for(i=1;i<=n;i++) want[a[i]]=1 }
    want[$3]{ print $3"\t"$2"\t"$1 }' /proc/mounts 2>/dev/null
}
# Bounded: `du` over a full filesystem walks the whole tree and can take minutes; cap it so disk-report
# stays responsive. On timeout, du is killed and output is empty — the caller reports that honestly.
smols_du_top1(){ smols_timeout "${SMOLS_DU_TIMEOUT:-20}" du -x -h -d1 "$1" 2>/dev/null; }
smols_du_summary(){ smols_timeout "${SMOLS_DU_HOG_TIMEOUT:-8}" du -x -sh "$1" 2>/dev/null | cut -f1; }

# --- diagnostics for ollama-doctor / freeze-forensics / runaway-hunter (Linux) ---
smols_gpu_name(){ nvidia-smi --query-gpu=name --format=csv,noheader 2>/dev/null | head -1; }
smols_gpu_vram_free(){ nvidia-smi --query-gpu=memory.free --format=csv,noheader,nounits 2>/dev/null | head -1; }   # MiB; empty if no NVIDIA
smols_gpu_vram_total(){ nvidia-smi --query-gpu=memory.total --format=csv,noheader,nounits 2>/dev/null | head -1; }
smols_boot_list(){ have journalctl && journalctl --list-boots --no-pager 2>/dev/null; }
# exit 0 = previous boot logged a clean shutdown, 1 = looks abrupt (freeze/power-loss), 2 = can't tell
smols_prev_boot_clean(){ have journalctl || return 2
  local prev; prev="$(journalctl -b -1 --no-pager -q 2>/dev/null | tail -40)"
  [ -z "$prev" ] && return 2   # no previous boot recorded in the journal -> unknown, NOT "abrupt"
  printf '%s\n' "$prev" | grep -qiE 'systemd-shutdown|Reached target.*(Power-Off|Reboot|Halt)|Shutting down'; }
smols_prev_boot_kernel_tail(){ have journalctl && journalctl -k -b -1 --no-pager -q 2>/dev/null | tail -n "${1:-40}"; }
smols_reset_reason(){ have journalctl && journalctl -k -b 0 --no-pager -q 2>/dev/null | grep -iE 'reset reason' | tail -1; }
smols_mce_summary(){
  if have ras-mc-ctl; then ras-mc-ctl --summary 2>/dev/null
  elif have journalctl; then journalctl -k -b -1 --no-pager -q 2>/dev/null | grep -iE 'machine check|hardware error|\bmce\b' | tail -5; fi; }
smols_watchdog_status(){
  local mods dev sd p daemon="" armed
  mods="$(lsmod 2>/dev/null | awk '$1 ~ /wdt|_tco|watchdog/{print $1}' | paste -sd, -)"
  dev="$(ls /dev/watchdog* 2>/dev/null | paste -sd, -)"
  sd="$(systemctl show -p RuntimeWatchdogUSec --value 2>/dev/null)"
  for p in $(pgrep -x 'watchdog|wd_keepalive|watchdogd' 2>/dev/null); do
    [ -n "$(tr -d '\0' < "/proc/$p/cmdline" 2>/dev/null)" ] && { daemon="$p"; break; }
  done
  if [ -z "$dev" ]; then armed=none
  elif { [ -n "$sd" ] && [ "$sd" != 0 ]; } || [ -n "$daemon" ]; then armed=yes
  else armed=no; fi
  echo "modules=${mods:-none} device=${dev:-none} systemd_runtime=${sd:-0} armed=${armed}"; }
# emit: pid age_seconds cpu mem stat comm  (sorted by cpu desc)
smols_procs_aged(){ ps -eo pid,etimes,pcpu,pmem,stat,comm --sort=-pcpu --no-headers 2>/dev/null; }
