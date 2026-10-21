#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-or-later
# Read-only power/C-state baseline. $1 = output dir, $2 = seconds
O=$1; N=$(( ${2:-120} / 10 )); mkdir -p $O
setpci -s 03:00.0 0x4c.w > $O/cam-pmcsr.txt; setpci -s 03:00.0 CAP_EXP+0x10.w > $O/cam-lnkctl.txt; setpci -s 00:1d.1 CAP_EXP+0x10.w > $O/rp10-lnkctl.txt
( for _ in $(seq $((N*10))); do echo "$(date +%s) $(cat /sys/class/power_supply/BAT0/current_now) $(cat /sys/class/power_supply/BAT0/voltage_now)"; sleep 1; done ) > $O/battery.txt &
turbostat --quiet --show Busy%,Bzy_MHz,Pkg%pc2,Pkg%pc3,Pkg%pc6,Pkg%pc7,Pkg%pc8,Pkg%pc9,PkgWatt,CorWatt -i 10 -n $N > $O/turbostat.txt 2>&1
wait; chown -R "${SUDO_UID:-$(id -u)}:${SUDO_GID:-$(id -g)}" "$O"
