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
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
exec make -C "$ROOT" --no-print-directory arch-pkg-dev "MAKEPKG_FLAGS=$*"
