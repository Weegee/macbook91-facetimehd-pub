#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
#
# promote-release.sh: copy a built release into release/<pkgver>/.
#
# This script does not commit, tag, push or publish anything.
#
# Optional gate: where a checkout carries release test scripts and a scan
# guard (see release_gate below), promotion also runs them over what a commit
# would carry, and removes the new release directory again when either fails.
# A checkout without them skips the gate. `--gate` runs the gate on its own,
# without promoting anything.
#
# SHA256SUMS covers exactly the files the repository tracks. The built
# package is gitignored and not covered; its checksum is recorded in
# STATUS.txt.
#
# Apple's firmware is never part of a release: the user downloads it with
# tools/macbook91-facetimehd-fetch-firmware.
#
# Text interface (house text HIG): status and messages go to stderr, the script
# prints no result on stdout; exit 0 done, 1 refused or failed, 2 usage error,
# 130 and 143 after SIGINT and SIGTERM.
#
set -euo pipefail

PROG=promote-release.sh
HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$HERE/.." && pwd)"

usage_full() {
	cat <<EOF
Usage: packaging/promote-release.sh [--seal VERSION | --gate]

Copies the built release into release/VERSION/ (PKGBUILD, .SRCINFO, install
scriptlet, source tarball, upstream.lock, STATUS.txt, SHA256SUMS) and runs the
release gate where this checkout has one. Commits, tags, pushes and publishes
nothing.

Examples:
  packaging/promote-release.sh                     promote the version in packaging/arch/PKGBUILD
  packaging/promote-release.sh --seal 20261026.02  redo SHA256SUMS after STATUS.txt is filled in
  packaging/promote-release.sh --gate              run the gate alone, promote nothing

Options:
      --seal VERSION   regenerate release/VERSION/SHA256SUMS
      --gate           run the release gate on its own
  -h, --help           this help
  -V, --version        version

Environment:
  TMPDIR   where the gate stages the files it scans (default /tmp)

Exit status:
  0    done
  1    refused or failed
  2    usage error
  130  interrupted by SIGINT (143 by SIGTERM)

Docs and bug reports: https://github.com/Weegee/macbook91-facetimehd-pub
EOF
}

# Messages: "prog: error: first line" and indented follow-up lines, on stderr.
err() { # FIRST [MORE...]
	printf '%s: error: %s\n' "$PROG" "$1" >&2
	shift
	local l
	for l in "$@"; do printf '  %s\n' "$l" >&2; done
}
say() { printf '%s\n' "$*" >&2; }
usage_error() { # FIRST [MORE...]
	err "$@"
	printf 'Usage: packaging/promote-release.sh [--seal VERSION | --gate]\n' >&2
	printf 'Example: packaging/promote-release.sh --gate\n' >&2
	printf 'Help: packaging/promote-release.sh --help\n' >&2
	exit 2
}

# -h and -V win over every other argument (HIL-1).
for a in "$@"; do
	case $a in
		-h|--help) usage_full; exit 0 ;;
		-V|--version) echo "$PROG $(cat "$ROOT/VERSION" 2>/dev/null || echo unknown)"; exit 0 ;;
	esac
done

# Files created by this run that a signal must clean up again.
STAGE='' CREATED=''
on_signal() { # INT or TERM
	trap - "$1"
	printf '\n%s: cancelled\n' "$PROG" >&2
	[ -z "$STAGE" ] || rm -rf -- "$STAGE"
	[ -z "$CREATED" ] || { rm -rf -- "$CREATED"; say "removed the unfinished $CREATED"; }
	kill -s "$1" "$$"
}
trap 'on_signal INT' INT
trap 'on_signal TERM' TERM

# --seal <version>: regenerate an existing release directory's SHA256SUMS.
# Promotion writes a STATUS.txt template that has to be filled in by hand, and
# STATUS.txt is itself covered by SHA256SUMS - so the checksums must be redone
# afterwards. Doing that by hand is the same kind of remembered step that left
# thirteen releases without a .SRCINFO.
SEALED=""
GATE_ONLY=0
case "${1:-}" in
	"") [ $# -eq 0 ] || usage_error "empty argument" ;;
	--seal)
		[ $# -ge 2 ] || usage_error "--seal needs a version"
		[ $# -eq 2 ] || usage_error "too many arguments after --seal"
		SEALED=$2 ;;
	--gate)
		[ $# -eq 1 ] || usage_error "--gate takes no argument"
		GATE_ONLY=1 ;;
	*) usage_error "unknown argument '$1'" ;;
esac

TRACKED_FILES='PKGBUILD .SRCINFO macbook91-facetimehd-dkms.install upstream.lock STATUS.txt'
seal() { # seal DIR
	local src="" f
	for f in "$1"/*.tar; do
		[ -e "$f" ] && { src=$(basename "$f"); break; }
	done
	[ -n "$src" ] || { err "no source tarball in $1" "Promote the release again to fill the directory."; return 1; }
	(cd "$1" && sha256sum -- $TRACKED_FILES "$src" > SHA256SUMS)
	say "sealed $1/SHA256SUMS over: $TRACKED_FILES $src"
}

# The gate scripts live in a directory that only some checkouts have; the glob
# finds it.
PRIV=""
for d in "$ROOT"/priv[a]te; do
	[ -d "$d" ] && PRIV="$d"
done

release_gate() {
	local t ex rc=0 found=0
	if [ -z "$PRIV" ]; then
		say "$PROG: note: the gate is skipped, this checkout has no gate scripts"
		return 0
	fi
	# 1. the private test scripts, each with its own counters.
	for t in "$PRIV"/tests/run-*.sh; do
		[ -e "$t" ] || continue
		found=1
		say "gate: running ${t#"$ROOT"/}"
		bash "$t" || { err "gate: ${t#"$ROOT"/} failed" "Its output above names the failing checks."; rc=1; }
	done
	[ "$found" -eq 1 ] || say "$PROG: warning: the gate found no test script"
	# 2. the scan guard over the files a commit would carry: tracked and
	# untracked-but-not-ignored files of the working tree, minus the paths
	# that are not published. Marker group P is a hard failure here.
	ex="$PRIV/export"
	if [ ! -f "$ex/guard.sh" ]; then
		err "gate: the scan guard is missing"
		return 1
	fi
	STAGE=$(mktemp -d "${TMPDIR:-/tmp}/promote-gate.XXXXXX")
	local -a specs=()
	mapfile -t specs < <(bash -c 'source "$1/lib.sh"; kit_pathspecs exclude "$1/private-paths.txt"' _ "$ex")
	[ "${#specs[@]}" -gt 0 ] || { err "gate: the list of unpublished paths is empty"; rm -rf "$STAGE"; STAGE=''; return 1; }
	(
		cd "$ROOT"
		git ls-files -z --cached --others --exclude-standard --deduplicate -- . "${specs[@]}" \
			| while IFS= read -r -d '' f; do
				{ [ -e "$f" ] || [ -L "$f" ]; } && printf '%s\0' "$f"
			done \
			| tar --null --no-recursion -T - -cf - | tar -C "$STAGE" -xf -
	) || { err "gate: could not stage the files" "Check the free space in ${TMPDIR:-/tmp}; TMPDIR chooses another directory."; rm -rf "$STAGE"; STAGE=''; return 1; }
	say "gate: scanning $(find "$STAGE" -type f | wc -l) files with the scan guard"
	bash "$ex/guard.sh" --conf "$ex" --strict tree "$STAGE" || { err "gate: the scan guard found hits" "Fix the hits it listed above, then run: packaging/promote-release.sh --gate"; rc=1; }
	rm -rf "$STAGE"; STAGE=''
	return "$rc"
}

if [ "$GATE_ONLY" -eq 1 ]; then
	release_gate
	exit $?
fi

if [ -n "$SEALED" ]; then
	DIR="$ROOT/release/$SEALED"
	[ -d "$DIR" ] || { err "no such release: $DIR" "Promote it first: packaging/promote-release.sh"; exit 1; }
	seal "$DIR"
	exit 0
fi

ARCH="$HERE/arch"
PKGVER=$(sed -n 's/^pkgver=//p' "$ARCH/PKGBUILD" | head -1)
PKGREL=$(sed -n 's/^pkgrel=//p' "$ARCH/PKGBUILD" | head -1)
PKGBASE=$(sed -n 's/^pkgbase=//p' "$ARCH/PKGBUILD" | head -1)

DEST="$ROOT/release/$PKGVER"
PKGNAME=$PKGBASE-dkms
PKGFILE="$ROOT/dist/${PKGNAME}-${PKGVER}-${PKGREL}-x86_64.pkg.tar.zst"
SRCTAR="$ROOT/dist/${PKGBASE}-${PKGVER}.tar"

# 1. release/<ver>/ is promoted, immutable history - never overwritten.
if [ -e "$DEST" ]; then
	err "$DEST already exists" "Release history is not overwritten. Raise the version in VERSION and packaging/arch/PKGBUILD first."
	exit 1
fi

# 2. .SRCINFO must actually match the PKGBUILD being promoted.
GENERATED_SRCINFO="$(cd "$ARCH" && makepkg --printsrcinfo)"
if ! diff -q <(printf '%s\n' "$GENERATED_SRCINFO") "$ARCH/.SRCINFO" >/dev/null 2>&1; then
	err "$ARCH/.SRCINFO does not match makepkg --printsrcinfo" "Regenerate it: make srcinfo"
	exit 1
fi

# 3. the built package for this exact version must already exist.
if [ ! -e "$PKGFILE" ]; then
	err "$PKGFILE does not exist" "Build it first: make arch-pkg"
	exit 1
fi

# 3b. ...from the tarball the PKGBUILD pins, not from some other build.
PINNED=$(sed -n "s/^sha256sums=('\([0-9a-f]*\)').*/\1/p" "$ARCH/PKGBUILD")
if [ ! -e "$SRCTAR" ] || [ "$(sha256sum "$SRCTAR" | cut -d' ' -f1)" != "$PINNED" ]; then
	err "$SRCTAR is missing or does not match the sha256sums in the PKGBUILD" "Build it again: make arch-pkg"
	exit 1
fi

install -dm755 "$DEST"
CREATED=$DEST
cp "$ARCH/PKGBUILD" "$DEST/PKGBUILD"
cp "$ARCH/.SRCINFO" "$DEST/.SRCINFO"
cp "$ARCH/macbook91-facetimehd-dkms.install" "$DEST/macbook91-facetimehd-dkms.install"
cp "$SRCTAR" "$DEST/$(basename "$SRCTAR")"
cp "$HERE/upstream.lock" "$DEST/upstream.lock"
cp "$PKGFILE" "$DEST/$(basename "$PKGFILE")"

PKGSUM=$(sha256sum "$PKGFILE" | cut -d' ' -f1)

cat > "$DEST/STATUS.txt" <<EOF
$PKGBASE $PKGVER-$PKGREL: TODO: WITHDRAWN / CANDIDATE / etc.

TODO: fill in before this release is considered documented. See prior
release/*/STATUS.txt for the level of detail expected: what changed, why,
what was measured, what is not yet verified, and the test suite counts.

Local build of the driver package (not tracked, not covered by SHA256SUMS, not published as a release file).
$PKGSUM  $(basename "$PKGFILE")
EOF

seal "$DEST"

# 3c. the optional gate. A failed gate removes the directory this run created,
# so a rerun is possible; nothing else was touched.
if ! release_gate; then
	rm -rf "${DEST:?}"
	CREATED=''
	err "the gate failed; removed $DEST" "Fix the cause and run the command again."
	exit 1
fi
CREATED=''

# 4. retention: keep the two newest release directories; older ones are
# pruned from the tree.
prune_old_releases() {
	local keep=2 n=0 v
	local vers=()
	for v in "$ROOT"/release/*/; do
		[ -d "$v" ] || continue
		vers+=("$(basename "$v")")
	done
	[ "${#vers[@]}" -gt 0 ] || return 0
	while read -r v; do
		[ -n "$v" ] || continue
		n=$((n + 1))
		if [ "$n" -le "$keep" ]; then
			continue
		fi
		rm -rf "${ROOT:?}/release/$v"
		say "pruned release/$v (kept the $keep newest)"
	done < <(printf '%s\n' "${vers[@]}" | sort -V -r)
}
prune_old_releases

say "promoted $PKGNAME $PKGVER-$PKGREL to $DEST"
say "Next: fill in $DEST/STATUS.txt, then re-seal the checksums it is part of:"
say "  $HERE/promote-release.sh --seal $PKGVER"
