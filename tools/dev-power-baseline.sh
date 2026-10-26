#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-or-later
#
# Read-only power/C-state baseline. Development tool; needs root.
#
# usage: dev-power-baseline.sh OUTDIR [SECONDS]
#
# Writes into OUTDIR only. Progress and the final line go to stderr; stdout
# stays empty. Exit status: 0 done, 1 failed, 2 usage error, 130 and 143 after
# SIGINT and SIGTERM.
set -u

PROG=dev-power-baseline.sh
VERSION=$(cat "$(dirname "$0")/../VERSION" 2>/dev/null) || VERSION=unknown

usage_full() {
	cat <<EOF
Usage: $PROG OUTDIR [SECONDS]

Records the camera's PCI power state and link control, then the battery
current and voltage (once per second) and the CPU package C-states
(turbostat, every 10 seconds) for SECONDS. Read-only; it changes no
setting. Needs root.

Examples:
  sudo tools/$PROG /var/tmp/baseline         120 seconds
  sudo tools/$PROG /var/tmp/baseline 60      60 seconds

Arguments:
  OUTDIR   directory for the result files (created if missing)
  SECONDS  measuring time, 10 or more, rounded down to a multiple of 10
           (default 120)

Options:
  -h, --help     this help
  -V, --version  version

Files written to OUTDIR:
  cam-pmcsr.txt, cam-lnkctl.txt, rp10-lnkctl.txt, battery.txt, turbostat.txt

Exit status:
  0    done
  1    failed
  2    usage error
  130  interrupted by SIGINT (143 by SIGTERM)

Docs and bug reports: https://github.com/Weegee/macbook91-facetimehd-pub
EOF
}

err() { printf '%s: error: %s\n' "$PROG" "$1" >&2; shift; for l in "$@"; do printf '  %s\n' "$l" >&2; done; }
usage_error() {
	err "$1"
	printf 'Usage: %s OUTDIR [SECONDS]\nExample: sudo tools/%s /var/tmp/baseline 60\nHelp: %s --help\n' "$PROG" "$PROG" "$PROG" >&2
	exit 2
}

for a in "$@"; do
	case $a in
		-h|--help) usage_full; exit 0 ;;
		-V|--version) echo "$PROG $VERSION"; exit 0 ;;
	esac
done
for a in "$@"; do
	case $a in -?*) usage_error "unknown option '$a'" ;; esac
done
[ $# -ge 1 ] || usage_error "OUTDIR is required"
[ $# -le 2 ] || usage_error "unexpected argument '$3'"
O=$1 SECS=${2:-120}
case $SECS in
	''|*[!0-9]*) usage_error "SECONDS must be a whole number, not '$SECS'" ;;
esac
[ "$SECS" -ge 10 ] || usage_error "SECONDS must be 10 or more, not '$SECS'"
N=$((SECS / 10))

for t in setpci turbostat; do
	command -v "$t" >/dev/null 2>&1 || { err "$t is not installed" "Install it: sudo pacman -S $([ "$t" = setpci ] && echo pciutils || echo linux-tools)"; exit 1; }
done
[ "$(id -u)" = 0 ] || { err "reading PCI registers and turbostat need root" "Run it with sudo: sudo $0 $*"; exit 1; }
mkdir -p "$O" || { err "cannot create $O"; exit 1; }

on_signal() { # INT or TERM
	trap - "$1"
	kill 0 2>/dev/null
	printf '\n%s: cancelled\n' "$PROG" >&2
	chown -R "${SUDO_UID:-$(id -u)}:${SUDO_GID:-$(id -g)}" "$O"
	kill -s "$1" "$$"
}
trap 'on_signal INT' INT
trap 'on_signal TERM' TERM

printf '%s: measuring for %s s, writing to %s\n' "$PROG" "$((N * 10))" "$O" >&2
setpci -s 03:00.0 0x4c.w > "$O/cam-pmcsr.txt"; setpci -s 03:00.0 CAP_EXP+0x10.w > "$O/cam-lnkctl.txt"; setpci -s 00:1d.1 CAP_EXP+0x10.w > "$O/rp10-lnkctl.txt"
( for _ in $(seq $((N*10))); do echo "$(date +%s) $(cat /sys/class/power_supply/BAT0/current_now) $(cat /sys/class/power_supply/BAT0/voltage_now)"; sleep 1; done ) > "$O/battery.txt" &
turbostat --quiet --show Busy%,Bzy_MHz,Pkg%pc2,Pkg%pc3,Pkg%pc6,Pkg%pc7,Pkg%pc8,Pkg%pc9,PkgWatt,CorWatt -i 10 -n "$N" > "$O/turbostat.txt" 2>&1
wait; chown -R "${SUDO_UID:-$(id -u)}:${SUDO_GID:-$(id -g)}" "$O"
printf '%s: done, results in %s\n' "$PROG" "$O" >&2
