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
set -euo pipefail

# --seal <version>: regenerate an existing release directory's SHA256SUMS.
# Promotion writes a STATUS.txt template that has to be filled in by hand, and
# STATUS.txt is itself covered by SHA256SUMS - so the checksums must be redone
# afterwards. Doing that by hand is the same kind of remembered step that left
# thirteen releases without a .SRCINFO.
SEALED=""
GATE_ONLY=0
if [ "${1:-}" = "--seal" ]; then
	SEALED="${2:?usage: promote-release.sh --seal <version>}"
elif [ "${1:-}" = "--gate" ]; then
	GATE_ONLY=1
fi

HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$HERE/.." && pwd)"

TRACKED_FILES='PKGBUILD .SRCINFO macbook91-facetimehd-dkms.install upstream.lock STATUS.txt'
seal() { # seal DIR
	local src="" f
	for f in "$1"/*.tar; do
		[ -e "$f" ] && { src=$(basename "$f"); break; }
	done
	[ -n "$src" ] || { echo "no source tarball in $1" >&2; return 1; }
	(cd "$1" && sha256sum -- $TRACKED_FILES "$src" > SHA256SUMS)
	echo "sealed $1/SHA256SUMS over: $TRACKED_FILES $src"
}

# The gate scripts live in a directory that only some checkouts have; the glob
# finds it.
PRIV=""
for d in "$ROOT"/priv[a]te; do
	[ -d "$d" ] && PRIV="$d"
done

release_gate() {
	local t ex stage rc=0 found=0
	if [ -z "$PRIV" ]; then
		echo "gate: skipped (no gate scripts in this checkout)"
		return 0
	fi
	# 1. the private test scripts, each with its own counters.
	for t in "$PRIV"/tests/run-*.sh; do
		[ -e "$t" ] || continue
		found=1
		echo "gate: running ${t#"$ROOT"/}"
		bash "$t" || { echo "gate: FAILED: ${t#"$ROOT"/}" >&2; rc=1; }
	done
	[ "$found" -eq 1 ] || echo "gate: no test script found"
	# 2. the scan guard over the files a commit would carry: tracked and
	# untracked-but-not-ignored files of the working tree, minus the paths
	# that are not published. Marker group P is a hard failure here.
	ex="$PRIV/export"
	if [ ! -f "$ex/guard.sh" ]; then
		echo "gate: FAILED: the scan guard is missing" >&2
		return 1
	fi
	stage=$(mktemp -d "${TMPDIR:-/tmp}/promote-gate.XXXXXX")
	local -a specs=()
	mapfile -t specs < <(bash -c 'source "$1/lib.sh"; kit_pathspecs exclude "$1/private-paths.txt"' _ "$ex")
	[ "${#specs[@]}" -gt 0 ] || { echo "gate: FAILED: no path list" >&2; rm -rf "$stage"; return 1; }
	(
		cd "$ROOT"
		git ls-files -z --cached --others --exclude-standard --deduplicate -- . "${specs[@]}" \
			| while IFS= read -r -d '' f; do
				{ [ -e "$f" ] || [ -L "$f" ]; } && printf '%s\0' "$f"
			done \
			| tar --null --no-recursion -T - -cf - | tar -C "$stage" -xf -
	) || { echo "gate: FAILED: could not stage the files" >&2; rm -rf "$stage"; return 1; }
	echo "gate: scanning $(find "$stage" -type f | wc -l) files with the scan guard"
	bash "$ex/guard.sh" --conf "$ex" --strict tree "$stage" || { echo "gate: FAILED: the scan guard found hits" >&2; rc=1; }
	rm -rf "$stage"
	return "$rc"
}

if [ "$GATE_ONLY" -eq 1 ]; then
	release_gate
	exit $?
fi

if [ -n "$SEALED" ]; then
	DIR="$ROOT/release/$SEALED"
	[ -d "$DIR" ] || { echo "no such release: $DIR" >&2; exit 1; }
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
	echo "refusing: $DEST already exists - release history is not overwritten" >&2
	exit 1
fi

# 2. .SRCINFO must actually match the PKGBUILD being promoted.
GENERATED_SRCINFO="$(cd "$ARCH" && makepkg --printsrcinfo)"
if ! diff -q <(printf '%s\n' "$GENERATED_SRCINFO") "$ARCH/.SRCINFO" >/dev/null 2>&1; then
	echo "refusing: makepkg --printsrcinfo differs from $ARCH/.SRCINFO - run make srcinfo first" >&2
	exit 1
fi

# 3. the built package for this exact version must already exist.
if [ ! -e "$PKGFILE" ]; then
	echo "refusing: $PKGFILE does not exist - build it first (make arch-pkg)" >&2
	exit 1
fi

# 3b. ...from the tarball the PKGBUILD pins, not from some other build.
PINNED=$(sed -n "s/^sha256sums=('\([0-9a-f]*\)').*/\1/p" "$ARCH/PKGBUILD")
if [ ! -e "$SRCTAR" ] || [ "$(sha256sum "$SRCTAR" | cut -d' ' -f1)" != "$PINNED" ]; then
	echo "refusing: $SRCTAR is missing or does not match the PKGBUILD's sha256sums - run make arch-pkg" >&2
	exit 1
fi

install -dm755 "$DEST"
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
	echo "refusing: the gate failed; removed $DEST" >&2
	exit 1
fi

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
		echo "pruned release/$v (kept the $keep newest)"
	done < <(printf '%s\n' "${vers[@]}" | sort -V -r)
}
prune_old_releases

echo "promoted $PKGNAME $PKGVER-$PKGREL to $DEST"
echo "fill in $DEST/STATUS.txt, then re-seal the checksums it is part of:"
echo "  $HERE/promote-release.sh --seal $PKGVER"
