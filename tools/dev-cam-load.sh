#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-or-later
#
# Load a macbook91-facetimehd.ko for testing without touching /usr/lib/firmware.
# Development tool; needs root.
#
# usage: dev-cam-load.sh KO FIRMWARE_ROOT   (FIRMWARE_ROOT contains facetimehd/)
#
# The result "insmod rc=N" goes to stdout. Exit status: 0 loaded, 1 failed,
# 2 usage error.
set -u

PROG=dev-cam-load.sh
VERSION=$(cat "$(dirname "$0")/../VERSION" 2>/dev/null) || VERSION=unknown

usage_full() {
	cat <<EOF
Usage: $PROG KO FIRMWARE_ROOT

Loads a built macbook91-facetimehd module for a test, with the firmware
search path pointed at FIRMWARE_ROOT, so /usr/lib/firmware stays untouched.
Needs root. Undo it with dev-cam-unload.sh.

Example:
  sudo tools/dev-cam-load.sh build/macbook91-facetimehd.ko /var/tmp/fwroot

Arguments:
  KO             the module file to load
  FIRMWARE_ROOT  directory that contains facetimehd/firmware.bin

Options:
  -h, --help     this help
  -V, --version  version

Output:
  The line "insmod rc=N" on stdout, N being the exit status of insmod.

Exit status:
  0  module loaded
  1  failed
  2  usage error

Docs and bug reports: https://github.com/Weegee/macbook91-facetimehd-pub
EOF
}

err() { printf '%s: error: %s\n' "$PROG" "$1" >&2; shift; for l in "$@"; do printf '  %s\n' "$l" >&2; done; }
usage_error() {
	err "$1"
	printf 'Usage: %s KO FIRMWARE_ROOT\nExample: sudo tools/%s build/macbook91-facetimehd.ko /var/tmp/fwroot\nHelp: %s --help\n' "$PROG" "$PROG" "$PROG" >&2
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
[ $# -ge 2 ] || usage_error "KO and FIRMWARE_ROOT are required"
[ $# -le 2 ] || usage_error "unexpected argument '$3'"

KO=$1 FWROOT=$2
[ -r "$KO" ] || { err "cannot read the module file $KO" "Check the path, or build the module first (docs/IMPLEMENTATION-PLAN.md)."; exit 1; }
[ -d "$FWROOT/facetimehd" ] || { err "$FWROOT/facetimehd is not a directory" "FIRMWARE_ROOT must contain facetimehd/firmware.bin."; exit 1; }
[ "$(id -u)" = 0 ] || { err "loading a module needs root" "Run it with sudo: sudo $0 $KO $FWROOT"; exit 1; }

printf '%s' "$FWROOT" > /sys/module/firmware_class/parameters/path \
	|| { err "cannot set the firmware search path"; exit 1; }
modprobe -a videodev videobuf2-common videobuf2-v4l2 videobuf2-dma-sg \
	|| { err "cannot load the video4linux modules the driver needs"; exit 1; }
insmod "$KO"; rc=$?
for _ in $(seq 50); do ls /dev/video* >/dev/null 2>&1 && break; sleep 0.1; done
echo "insmod rc=$rc"
[ "$rc" = 0 ] || { err "insmod failed with status $rc" "See: dmesg | tail"; exit 1; }
