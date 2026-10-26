#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
#
# Build macbook91-facetimehd-dkms from the working tree: a
# wrapper for `make arch-pkg-dev` (see the root Makefile), which assembles
# the driver tree, writes the source tarball from the tracked files as they
# are on disk and builds in a fresh build/arch. Packages land in dist/.
# Arguments go to makepkg. A release is built with `make arch-pkg`, which also
# requires a committed tree and the tarball checksum pinned in the PKGBUILD.
#
# Text interface (house text HIG): -h/--help and -V/--version are answered
# here, every other argument is makepkg's.
#
set -euo pipefail

PROG=make-package.sh
ROOT="$(cd "$(dirname "$0")/.." && pwd)"

for a in "$@"; do
	case $a in
		-h|--help)
			cat <<EOF
Usage: packaging/make-package.sh [MAKEPKG_OPTIONS]

Builds macbook91-facetimehd-dkms from the working tree (make arch-pkg-dev):
assembles the driver tree, writes the source tarball from the tracked files as
they are on disk and builds in a fresh build/arch. Packages land in dist/.
Every other argument goes to makepkg. A release is built with: make arch-pkg

Examples:
  packaging/make-package.sh                 build the package
  packaging/make-package.sh --syncdeps      let makepkg install missing build dependencies

Options:
  -h, --help       this help
  -V, --version    version

Exit status:
  0  package built
  1  error (the message names the failing step)

Docs and bug reports: https://github.com/Weegee/macbook91-facetimehd-pub
EOF
			exit 0 ;;
		-V|--version) echo "$PROG $(cat "$ROOT/VERSION" 2>/dev/null || echo unknown)"; exit 0 ;;
	esac
done

exec make -C "$ROOT" --no-print-directory arch-pkg-dev "MAKEPKG_FLAGS=$*"
