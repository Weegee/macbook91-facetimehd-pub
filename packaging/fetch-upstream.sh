#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-or-later
# Assemble src/macbook91-facetimehd/ from the pinned upstream commit, the numbered
# patches and the overlay. packaging/upstream.lock is the only record of
# what those bytes must be: a base tree or patch that does not match it is
# a hard failure, and a patch the lockfile does not list is refused.
#
# usage: packaging/fetch-upstream.sh [UPSTREAM_CLONE]
#   UPSTREAM_CLONE  existing clone to fetch into (default build/upstream)
set -euo pipefail

ROOT=$(cd "$(dirname "$0")/.." && pwd)
LOCK=$ROOT/packaging/upstream.lock
OUT=$ROOT/src/macbook91-facetimehd
CLONE=${1:-$ROOT/build/upstream}

lock() { awk -v k="$1" '$1 == k { print $2 }' "$LOCK"; }
die() { echo "ERROR: $*" >&2; exit 1; }

repo=$(lock driver.repo) commit=$(lock driver.commit) tree=$(lock driver.tree)
[ -n "$repo" ] && [ -n "$commit" ] && [ -n "$tree" ] || die "incomplete lockfile"

if [ ! -d "$CLONE/.git" ]; then
	git clone -q --no-checkout "$repo" "$CLONE"
fi
git -C "$CLONE" cat-file -e "$commit^{commit}" 2>/dev/null || git -C "$CLONE" fetch -q origin "$commit"
[ "$(git -C "$CLONE" rev-parse "$commit^{tree}")" = "$tree" ] || die "tree of $commit does not match lockfile"

rm -rf "$OUT"
mkdir -p "$OUT"
git -C "$CLONE" archive "$commit" | tar -x -C "$OUT"
rm -f "$OUT/dkms.conf" "$OUT/Makefile" "$OUT/README.md" "$OUT/.gitignore"
rm -rf "$OUT/firmware"

# Apply patches strictly in order; git apply refuses fuzz.
for p in "$ROOT"/patches/[0-9][0-9][0-9][0-9]-*.patch; do
	[ -e "$p" ] || continue
	n=$(basename "$p" | cut -c1-4)
	want=$(lock "patch.$n.sha256")
	[ -n "$want" ] || die "patch $n is not listed in upstream.lock"
	[ "$(sha256sum "$p" | cut -d' ' -f1)" = "$want" ] || die "patch $n does not match its lockfile hash"
	git -C "$ROOT" apply -p1 --whitespace=nowarn --directory=src/macbook91-facetimehd "$p" || die "patch $n does not apply"
done

install -m644 "$ROOT/packaging/overlay/Makefile" "$OUT/Makefile"
install -m644 "$ROOT/packaging/overlay/Kbuild" "$OUT/Kbuild"
install -m644 "$ROOT/packaging/overlay/dkms.conf" "$OUT/dkms.conf"
install -m644 "$ROOT/packaging/overlay/TESTED-SERIES" "$OUT/TESTED-SERIES"

# Integrity record checked by the Makefile's check target before every build.
# dkms.conf is left out: make install writes the version into it.
(cd "$OUT" && find . -type f ! -name dkms.conf ! -name SOURCES.sha256 -printf '%P\n' \
	| LC_ALL=C sort | xargs -d '\n' sha256sum > SOURCES.sha256)
echo "assembled $OUT from $commit + $(ls "$ROOT"/patches/*.patch 2>/dev/null | wc -l) patches"
