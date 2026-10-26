#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-or-later
#
# Unload macbook91-facetimehd and clear the temporary firmware search path.
# Development tool; needs root. Counterpart of dev-cam-load.sh.
#
# The result "rmmod rc=N" goes to stdout. Exit status: 0 unloaded, 1 failed,
# 2 usage error.
set -u

PROG=dev-cam-unload.sh
VERSION=$(cat "$(dirname "$0")/../VERSION" 2>/dev/null) || VERSION=unknown

usage_full() {
	cat <<EOF
Usage: $PROG

Unloads the macbook91-facetimehd module and clears the firmware search path
that dev-cam-load.sh set. Needs root.

Example:
  sudo tools/$PROG

Options:
  -h, --help     this help
  -V, --version  version

Output:
  The line "rmmod rc=N" on stdout, N being the exit status of rmmod.

Exit status:
  0  module unloaded
  1  failed
  2  usage error

Docs and bug reports: https://github.com/Weegee/macbook91-facetimehd-pub
EOF
}

err() { printf '%s: error: %s\n' "$PROG" "$1" >&2; shift; for l in "$@"; do printf '  %s\n' "$l" >&2; done; }

for a in "$@"; do
	case $a in
		-h|--help) usage_full; exit 0 ;;
		-V|--version) echo "$PROG $VERSION"; exit 0 ;;
	esac
done
if [ $# -gt 0 ]; then
	case $1 in -?*) err "unknown option '$1'" ;; *) err "unexpected argument '$1'" ;; esac
	printf 'Usage: %s\nExample: sudo tools/%s\nHelp: %s --help\n' "$PROG" "$PROG" "$PROG" >&2
	exit 2
fi
[ "$(id -u)" = 0 ] || { err "unloading a module needs root" "Run it with sudo: sudo $0"; exit 1; }

rmmod macbook91_facetimehd; rc=$?
printf '' > /sys/module/firmware_class/parameters/path \
	|| err "cannot clear the firmware search path"
echo "rmmod rc=$rc"
[ "$rc" = 0 ] || { err "rmmod failed with status $rc" "See: dmesg | tail"; exit 1; }
