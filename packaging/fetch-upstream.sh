#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-or-later
# Assemble src/macbook91-facetimehd/ from the pinned upstream commit, the numbered
# patches and the overlay. packaging/upstream.lock is the only record of
# what those bytes must be: a base tree or patch that does not match it is
# a hard failure, and a patch the lockfile does not list is refused.
#
# usage: packaging/fetch-upstream.sh [--timeout SEC] [UPSTREAM_CLONE]
#   UPSTREAM_CLONE  existing clone to fetch into (default build/upstream)
#
# Text interface (house text HIG): messages and status go to stderr, the script
# prints no result on stdout; exit 0 done, 1 error, 2 usage error.
set -euo pipefail

PROG=fetch-upstream.sh
ROOT=$(cd "$(dirname "$0")/.." && pwd)
LOCK=$ROOT/packaging/upstream.lock
OUT=$ROOT/src/macbook91-facetimehd
TIMEOUT=30

usage_full() {
	cat <<EOF
Usage: packaging/fetch-upstream.sh [--timeout SEC] [UPSTREAM_CLONE]

Assembles src/macbook91-facetimehd/ from the upstream commit pinned in
packaging/upstream.lock, the numbered patches and the overlay. A tree or patch
that does not match the lockfile is a hard failure.

Examples:
  packaging/fetch-upstream.sh                      clone into build/upstream if needed
  packaging/fetch-upstream.sh ~/src/facetimehd     fetch into an existing clone

Options:
      --timeout SEC   give up when a download stalls for SEC seconds (default 30)
  -h, --help          this help
  -V, --version       version

Exit status:
  0  assembled
  1  error
  2  usage error

Docs and bug reports: https://github.com/Weegee/macbook91-facetimehd-pub
EOF
}
err() { # FIRST [MORE...]
	printf '%s: error: %s\n' "$PROG" "$1" >&2
	shift
	local l
	for l in "$@"; do printf '  %s\n' "$l" >&2; done
}
die() { err "$@"; exit 1; }
usage_error() { # FIRST [MORE...]
	err "$@"
	printf 'Usage: packaging/fetch-upstream.sh [--timeout SEC] [UPSTREAM_CLONE]\n' >&2
	printf 'Example: packaging/fetch-upstream.sh\n' >&2
	printf 'Help: packaging/fetch-upstream.sh --help\n' >&2
	exit 2
}

# -h and -V win over every other argument (HIL-1).
for a in "$@"; do
	case $a in
		--) break ;;
		-h|--help) usage_full; exit 0 ;;
		-V|--version) echo "$PROG $(cat "$ROOT/VERSION" 2>/dev/null || echo unknown)"; exit 0 ;;
	esac
done
POS=()
while [ $# -gt 0 ]; do
	case $1 in
		--timeout)
			[ $# -ge 2 ] || usage_error "option '--timeout' needs a value"
			TIMEOUT=$2; shift 2 ;;
		--timeout=*) TIMEOUT=${1#*=}; shift ;;
		--) shift; POS+=("$@"); break ;;
		-?*) usage_error "unknown option '$1'" ;;
		*) POS+=("$1"); shift ;;
	esac
done
[ "${#POS[@]}" -le 1 ] || usage_error "too many arguments: ${POS[*]}"
[[ $TIMEOUT =~ ^[0-9]+$ ]] && [ "$TIMEOUT" -ge 1 ] && [ "$TIMEOUT" -le 3600 ] ||
	usage_error "--timeout $TIMEOUT is out of range 1 to 3600 seconds"
CLONE=${POS[0]:-$ROOT/build/upstream}

lock() { awk -v k="$1" '$1 == k { print $2 }' "$LOCK"; }
# Network calls stop when a transfer stalls (FOR-7).
net() { git -c http.lowSpeedLimit=1 -c "http.lowSpeedTime=$TIMEOUT" "$@"; }

repo=$(lock driver.repo) commit=$(lock driver.commit) tree=$(lock driver.tree)
[ -n "$repo" ] && [ -n "$commit" ] && [ -n "$tree" ] ||
	die "packaging/upstream.lock lacks driver.repo, driver.commit or driver.tree" \
		"Restore it from git: git checkout -- packaging/upstream.lock"

if [ ! -d "$CLONE/.git" ]; then
	echo "Cloning $repo into $CLONE" >&2
	net clone -q --no-checkout "$repo" "$CLONE" ||
		die "cannot clone $repo" "Check the network connection and run the command again. --timeout SEC changes the $TIMEOUT s stall limit."
fi
if ! git -C "$CLONE" cat-file -e "$commit^{commit}" 2>/dev/null; then
	echo "Fetching $commit into $CLONE" >&2
	net -C "$CLONE" fetch -q origin "$commit" ||
		die "cannot fetch $commit from $repo" "Check the network connection and run the command again. --timeout SEC changes the $TIMEOUT s stall limit."
fi
[ "$(git -C "$CLONE" rev-parse "$commit^{tree}")" = "$tree" ] ||
	die "the tree of $commit does not match driver.tree in packaging/upstream.lock" \
		"The clone in $CLONE holds different content than the lockfile pins. Nothing was assembled."

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
	[ -n "$want" ] || die "patch $n is not listed in packaging/upstream.lock" "Add its sha256 as patch.$n.sha256, or remove the patch."
	[ "$(sha256sum "$p" | cut -d' ' -f1)" = "$want" ] || die "patch $n does not match its hash in packaging/upstream.lock" "Patches are not edited after they are locked; add a new numbered patch instead."
	git -C "$ROOT" apply -p1 --whitespace=nowarn --directory=src/macbook91-facetimehd "$p" || die "patch $n does not apply to the upstream tree" "src/macbook91-facetimehd is only partly assembled. Fix the patch and run the command again."
done

# Abweichung von FEH-2: packaging/overlay/Makefile still prints "ERROR: ..." (DKMS shows it
# in make.log). The file is part of the module tree, whose bytes the identity proof of a
# release compares with the previous one, so its wording changes with the next driver
# change, not in a release that changes only text interfaces.
install -m644 "$ROOT/packaging/overlay/Makefile" "$OUT/Makefile"
install -m644 "$ROOT/packaging/overlay/Kbuild" "$OUT/Kbuild"
install -m644 "$ROOT/packaging/overlay/dkms.conf" "$OUT/dkms.conf"
install -m644 "$ROOT/packaging/overlay/TESTED-SERIES" "$OUT/TESTED-SERIES"

# Integrity record checked by the Makefile's check target before every build.
# dkms.conf is left out: make install writes the version into it.
(cd "$OUT" && find . -type f ! -name dkms.conf ! -name SOURCES.sha256 -printf '%P\n' \
	| LC_ALL=C sort | xargs -d '\n' sha256sum > SOURCES.sha256)
n=$(ls "$ROOT"/patches/*.patch 2>/dev/null | wc -l) || n=0
echo "assembled $OUT from $commit + $n $([ "$n" = 1 ] && echo patch || echo patches)" >&2
