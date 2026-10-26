#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-or-later
#
# Read-only root diagnosis. Writes only into OUTDIR. Development tool.
#
# usage: dev-root-diag.sh OUTDIR
#
# The final line goes to stderr; stdout stays empty. Exit status: 0 done,
# 1 failed, 2 usage error.
set -u

PROG=dev-root-diag.sh
VERSION=$(cat "$(dirname "$0")/../VERSION" 2>/dev/null) || VERSION=unknown

usage_full() {
	cat <<EOF
Usage: $PROG OUTDIR

Collects the root-only hardware facts the camera analysis needs: dmidecode,
lspci -vvv and -xxxx for the camera and its root port, and a copy of the
ACPI tables. Read-only; it changes no setting. Needs root. The raw files
contain serial numbers: keep them outside the repository and publish only
sanitized excerpts.

Example:
  sudo tools/$PROG /var/tmp/diag

Argument:
  OUTDIR  directory for the result files (created if missing)

Options:
  -h, --help     this help
  -V, --version  version

Files written to OUTDIR:
  dmidecode.txt, lspci-cam-root.txt, lspci-rp10-root.txt, lspci-cam-cfg.txt,
  acpi/ (copy of /sys/firmware/acpi/tables)

Exit status:
  0  done
  1  failed
  2  usage error

Docs and bug reports: https://github.com/Weegee/macbook91-facetimehd-pub
EOF
}

err() { printf '%s: error: %s\n' "$PROG" "$1" >&2; shift; for l in "$@"; do printf '  %s\n' "$l" >&2; done; }
usage_error() {
	err "$1"
	printf 'Usage: %s OUTDIR\nExample: sudo tools/%s /var/tmp/diag\nHelp: %s --help\n' "$PROG" "$PROG" "$PROG" >&2
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
[ $# -le 1 ] || usage_error "unexpected argument '$2'"
O=$1

for t in dmidecode lspci; do
	command -v "$t" >/dev/null 2>&1 || { err "$t is not installed" "Install it: sudo pacman -S $([ "$t" = dmidecode ] && echo dmidecode || echo pciutils)"; exit 1; }
done
[ "$(id -u)" = 0 ] || { err "dmidecode and the ACPI tables need root" "Run it with sudo: sudo $0 $O"; exit 1; }
mkdir -p "$O/acpi" || { err "cannot create $O"; exit 1; }

dmidecode > "$O/dmidecode.txt" 2>&1
lspci -vvv -nn -s 03:00.0 > "$O/lspci-cam-root.txt" 2>&1
lspci -vvv -nn -s 00:1d.1 > "$O/lspci-rp10-root.txt" 2>&1
lspci -xxxx -s 03:00.0 > "$O/lspci-cam-cfg.txt" 2>&1
cp -r /sys/firmware/acpi/tables/. "$O/acpi/" 2>/dev/null
chown -R "${SUDO_UID:-$(id -u)}:${SUDO_GID:-$(id -g)}" "$O"
printf '%s: done, results in %s\n' "$PROG" "$O" >&2
