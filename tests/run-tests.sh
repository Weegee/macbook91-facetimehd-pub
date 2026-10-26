#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
#
# Hermetic tests for macbook91-facetimehd: no root, no camera, no suspend.
# Network is used only when packaging/fetch-upstream.sh has to clone the
# upstream driver into build/upstream for the first time.
#
# Prints one line per check and a summary "N passed, N failed, N blocked";
# exit status 1 if anything failed. Blocked rows need the machine or a
# missing tool and are named, never counted as passed.
#
set -u

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT" || exit 1
VERSION=$(cat VERSION)
MOD_DIR=src/macbook91-facetimehd
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT

passed=0 failed=0 blocked=0
ok() { printf 'PASS     %s\n' "$*"; passed=$((passed + 1)); }
bad() { printf 'FAIL     %s\n' "$*"; failed=$((failed + 1)); }
blk() { printf 'BLOCKED  %s\n' "$*"; blocked=$((blocked + 1)); }
check() { # check NAME COMMAND...
	local name=$1; shift
	if "$@" >"$T/out" 2>&1; then ok "$name"; else bad "$name"; sed 's/^/         | /' "$T/out" | head -15; fi
}

SHELLS=(tools/macbook91-facetimehd-verify tools/macbook91-facetimehd-kernel-series
	tools/dev-cam-load.sh tools/dev-cam-unload.sh tools/dev-power-baseline.sh tools/dev-root-diag.sh
	packaging/fetch-upstream.sh packaging/make-package.sh packaging/promote-release.sh
	packaging/arch/macbook91-facetimehd-dkms.install tests/run-tests.sh)
# The firmware fetch script the user runs. It is GPL-2.0-only (adapted from
# patjak/facetimehd-firmware), so it is not in SHELLS.
FWX=tools/macbook91-facetimehd-fetch-firmware

# --- static checks -----------------------------------------------------------
for f in "${SHELLS[@]}" "$FWX"; do check "bash -n $f" bash -n "$f"; done
if command -v shellcheck >/dev/null; then
	check "shellcheck (warnings) on packaged and packaging scripts" shellcheck -S warning -s bash \
		tools/macbook91-facetimehd-verify tools/macbook91-facetimehd-kernel-series \
		packaging/fetch-upstream.sh packaging/make-package.sh packaging/promote-release.sh \
		packaging/arch/macbook91-facetimehd-dkms.install "$FWX"
else
	blk "shellcheck not installed"
fi
check "packaging/mkdist.py compiles" python3 -c "import ast,sys; ast.parse(open('packaging/mkdist.py').read())"
license_ok() { # README.md maps every path; these files name their license themselves
	grep -qx 'Version 3, 29 June 2007' LICENSE &&
	grep -qx 'Version 2, June 1991' LICENSES/GPL-2.0-only.txt &&
	grep -qx 'Version 2, June 1991' LICENSES/GPL-2.0-or-later.txt &&
	cmp -s LICENSE LICENSES/GPL-3.0-or-later.txt &&
	[ ! -e LICENSES/MIT.txt ] &&
	grep -qx "license=('GPL-2.0-only' 'GPL-2.0-or-later' 'GPL-3.0-or-later')" packaging/arch/PKGBUILD || return 1
	local f
	# GPLv2 section 3: what builds and installs the module is part of its source.
	for f in packaging/overlay/Kbuild packaging/overlay/Makefile packaging/overlay/dkms.conf \
		packaging/overlay/TESTED-SERIES; do
		head -1 "$f" | grep -qx '# SPDX-License-Identifier: GPL-2.0-or-later' || { echo "no GPL-2.0-or-later SPDX line: $f"; return 1; }
	done
	for f in "${SHELLS[@]}" Makefile packaging/mkdist.py packaging/upstream.lock packaging/arch/PKGBUILD \
		tools/macbook91-facetimehd-series.hook .gitignore; do
		head -2 "$f" | grep -qx '# SPDX-License-Identifier: GPL-3.0-or-later' || { echo "no GPL-3.0-or-later SPDX line: $f"; return 1; }
	done
	# The extractor is adapted from patjak/facetimehd-firmware (GPL-2.0), so it stays GPL-2.0-only.
	head -2 "$FWX" | grep -qx '# SPDX-License-Identifier: GPL-2.0-only' || { echo "no GPL-2.0-only SPDX line: $FWX"; return 1; }
}
check "license texts, PKGBUILD licenses and the SPDX line of every own script and build file" license_ok

# --- versions and metadata ------------------------------------------------------
check "VERSION has the form YYYYMMDD.NN" grep -qxE '[0-9]{8}\.[0-9]{2}' VERSION
check "PKGBUILD pkgver equals VERSION" grep -qx "pkgver=$VERSION" packaging/arch/PKGBUILD
check "CHANGELOG has an entry for VERSION" grep -q "^## $VERSION" docs/CHANGELOG.md
if command -v makepkg >/dev/null; then
	srcinfo_ok() { diff <(cd packaging/arch && makepkg --printsrcinfo) packaging/arch/.SRCINFO; }
	check ".SRCINFO matches makepkg --printsrcinfo" srcinfo_ok
else
	blk "makepkg not installed (.SRCINFO)"
fi
names_ok() {
	grep -qx 'obj-m := macbook91-facetimehd.o' packaging/overlay/Kbuild &&
	grep -qx 'BUILT_MODULE_NAME\[0\]="macbook91-facetimehd"' packaging/overlay/dkms.conf &&
	grep -qx 'PACKAGE_NAME="macbook91-facetimehd"' packaging/overlay/dkms.conf &&
	grep -qx 'MOD=macbook91_facetimehd' tools/macbook91-facetimehd-verify &&
	grep -qx 'pkgbase=macbook91-facetimehd' packaging/arch/PKGBUILD
}
check "module and package names agree (overlay, dkms.conf, PKGBUILD, verify)" names_ok
check "dkms.conf uses no directive dkms 3 reports as deprecated" \
	bash -c "! grep -qE '^(CLEAN|MODULES_CONF|REMAKE_INITRD|OBSOLETE_BY)' packaging/overlay/dkms.conf"

fw_pin_ok() {
	# The two hashes are the ones the fetch script pins (fw_fetch_ok compares them).
	grep -qx '240ef2e991f1d089d8228ce11d92b66bfa4b3d7289ec4fee228b64a713024330 firmware.bin' tools/macbook91-facetimehd-verify &&
	grep -qx 'b7a38aef2755721bb28c92d84a15654b17e9fb3b0a0f088a384a981fc8fe16d6 1675_01XX.dat' tools/macbook91-facetimehd-verify &&
	grep -qx "    depends=('dkms')" packaging/arch/PKGBUILD &&
	! grep -q 'facetimehd-firmware' packaging/arch/PKGBUILD packaging/arch/.SRCINFO
}
check "driver package needs no firmware package; verify pins the firmware hashes" fw_pin_ok
fw_fetch_ok() {
	# The user runs the fetch script, on their own responsibility: it is installed, pins
	# the same hashes as the verify tool, and asks before it downloads anything.
	local n h rc=0
	for n in firmware.bin 1675_01XX.dat; do
		h=$(awk -v n="$n" '$2 == n {print $1}' <(sed -n '/^FW_SUMS="/,/^"/p' tools/macbook91-facetimehd-verify))
		[ -n "$h" ] || { echo "verify tool pins no hash for $n"; rc=1; continue; }
		grep -q "$h" "$FWX" || { echo "$n: the fetch script does not pin this hash"; rc=1; }
	done
	git ls-files -s -- "$FWX" | grep -q '^100755 ' || { echo "$FWX is not tracked as executable"; rc=1; }
	grep -q 'install -Dm755 tools/macbook91-facetimehd-fetch-firmware' Makefile || { echo "make install does not install the fetch script"; rc=1; }
	grep -q '"tools/macbook91-facetimehd-fetch-firmware"' packaging/mkdist.py || { echo "the fetch script is not in the tarball"; rc=1; }
	grep -q 'Type yes to continue' "$FWX" || { echo "the fetch script does not ask first"; rc=1; }
	[ ! -e packaging/firmware ] || { echo "packaging/firmware still exists"; rc=1; }
	return $rc
}
check "firmware fetch script: pins = verify pins, installed, in the tarball, asks first" fw_fetch_ok
fw_ask_ok() {
	# Without a terminal and without --yes the script downloads nothing and fails.
	local out
	out=$(setsid -w "$FWX" "$T/fw-noask" </dev/null 2>&1) && return 1
	grep -q 'aborted, nothing downloaded' <<<"$out" && [ ! -e "$T/fw-noask" ]
}
check "firmware fetch script refuses to run without an explicit yes" fw_ask_ok
fw_note_ok() {
	# The install message says loudly that the firmware is missing and whose terms apply.
	local f=packaging/arch/macbook91-facetimehd-dkms.install
	grep -q 'IMPORTANT: THE CAMERA DOES NOT WORK YET - APPLE FIRMWARE NEEDED' "$f" &&
	grep -q 'sudo macbook91-facetimehd-fetch-firmware' "$f" &&
	grep -q 'does NOT contain' "$f" && grep -q 'own account and at your own' "$f"
}
check "install message carries the firmware notice" fw_note_ok
fw_blob_ok() {
	# No tracked file may be one of the four Apple files the extractor pins (firmware.bin,
	# the 1675 set file, AppleCameraInterface, AppleCameraAssistant). Text that names a hash is fine.
	local pins
	pins=$(grep -ohE '\b[0-9a-f]{64}\b' "$FWX" | sort -u)
	[ -n "$pins" ] || { echo "no pinned hashes found"; return 1; }
	! git ls-files -z -- . ':!private' | xargs -0 -r sha256sum 2>/dev/null | cut -d' ' -f1 | sort -u |
		comm -12 - <(printf '%s\n' "$pins") | grep .
}
check "no tracked file is one of the pinned Apple files" fw_blob_ok
verify_wq_ok() {
	# A stub journalctl with the 7.2 workqueue warning must turn the log check into WARN.
	mkdir -p "$T/stub" &&
	printf '#!/bin/sh\necho "workqueue: work func fthd_idle_work [macbook91_facetimehd] enqueued on deprecated workqueue. Use system_{percpu|dfl}_wq instead."\n' > "$T/stub/journalctl" &&
	chmod +x "$T/stub/journalctl" &&
	PATH="$T/stub:$PATH" timeout 120 tools/macbook91-facetimehd-verify --no-capture 2>&1 |
		grep -q 'WARN  kernel log: .* 1 workqueue warnings naming macbook91_facetimehd'
}
check "verify warns about a workqueue warning naming the module" verify_wq_ok

# --- kernel series note ----------------------------------------------------------
# DKMS builds for every kernel; packaging/overlay/TESTED-SERIES is the one list
# of tested series, and the pacman hook only prints a note for the others.
KS=tools/macbook91-facetimehd-kernel-series
ks_list_ok() {
	local want
	want=$(grep -vE '^(#|$)' packaging/overlay/TESTED-SERIES | paste -sd' ')
	[ -n "$want" ] && [ "$(bash "$KS" --list --series-file packaging/overlay/TESTED-SERIES)" = "$want" ]
}
check "TESTED-SERIES parses, kernel-series --list returns it" ks_list_ok
ks_hook_ok() {
	local d=$T/ks out rc r
	rm -rf "$d"; mkdir -p "$d/modules"
	printf '# comment\n6.18\n\n7.3\n' > "$d/TESTED-SERIES"
	for r in 6.18.55-2-cachyos-lts 7.3.0-4-cachyos 7.30.1-1 7.4.0-1-cachyos custom; do
		mkdir -p "$d/modules/$r"; : > "$d/modules/$r/vmlinuz"
	done
	# A modules directory without a kernel image (left behind by a removed kernel).
	mkdir -p "$d/modules/7.1.9-1-leftover"
	out=$(bash "$KS" --hook --series-file "$d/TESTED-SERIES" --modules-root "$d/modules" 2>&1 >/dev/null)
	rc=$?
	[ "$rc" = 0 ] || { echo "exit $rc"; return 1; }
	[ -z "$(bash "$KS" --hook --series-file "$d/TESTED-SERIES" --modules-root "$d/modules" 2>/dev/null)" ] ||
		{ echo "notes on stdout"; return 1; }
	[ "$(grep -c '^macbook91-facetimehd: note: ' <<<"$out")" = 3 ] || { echo "$out"; return 1; }
	grep -qF 'not tested on Linux 7.4 (kernel 7.4.0-1-cachyos); tested series: 6.18, 7.3.' <<<"$out" &&
	grep -qF 'not tested on Linux 7.30 (kernel 7.30.1-1)' <<<"$out" &&
	grep -qF 'not tested on kernel custom;' <<<"$out" &&
	grep -qF '  If the camera misbehaves on that kernel, boot the LTS kernel.' <<<"$out" &&
	! grep -qE '6\.18\.55|7\.3\.0|leftover' <<<"$out" || { echo "$out"; return 1; }
}
check "kernel-series --hook: one note per installed kernel of an untested series, exit 0" ks_hook_ok
ks_err_ok() {
	local rc
	bash "$KS" --list --series-file "$T/missing" >/dev/null 2>&1; rc=$?
	[ "$rc" = 1 ] || { echo "missing list: exit $rc"; return 1; }
	printf '7.3.0\n' > "$T/bad-series"
	bash "$KS" --list --series-file "$T/bad-series" >/dev/null 2>&1; rc=$?
	[ "$rc" = 1 ] || { echo "malformed list: exit $rc"; return 1; }
	bash "$KS" --bogus >/dev/null 2>&1; rc=$?
	[ "$rc" = 2 ] || { echo "bad argument: exit $rc"; return 1; }
}
check "kernel-series: exit 1 for a missing or malformed list, 2 for a bad argument" ks_err_ok
ks_hookfile_ok() {
	local h=tools/macbook91-facetimehd-series.hook
	grep -qx 'When = PostTransaction' "$h" &&
	grep -qx 'Target = usr/lib/modules/\*/vmlinuz' "$h" &&
	grep -qx 'Target = usr/src/macbook91-facetimehd-\*/dkms.conf' "$h" &&
	grep -qx 'Exec = /usr/lib/macbook91-facetimehd/kernel-series --hook' "$h" &&
	! grep -q 'AbortOnFail' "$h" &&
	! grep -q 'BUILD_EXCLUSIVE' packaging/overlay/dkms.conf
}
check "series hook runs after the transaction, cannot abort it; dkms.conf builds for every kernel" ks_hookfile_ok

# --- provenance --------------------------------------------------------------------
lock_ok() {
	local p n want have rc=0
	for p in patches/[0-9][0-9][0-9][0-9]-*.patch; do
		n=$(basename "$p" | cut -c1-4)
		want=$(awk -v k="patch.$n.sha256" '$1 == k {print $2}' packaging/upstream.lock)
		have=$(sha256sum "$p" | cut -d' ' -f1)
		[ "$want" = "$have" ] || { echo "patch $n: lock ${want:-missing}, file $have"; rc=1; }
	done
	for n in $(awk '$1 ~ /^patch\.[0-9]+\.sha256$/ {split($1, a, "."); print a[2]}' packaging/upstream.lock); do
		ls patches/"$n"-*.patch >/dev/null 2>&1 || { echo "lock lists patch $n, no file"; rc=1; }
	done
	return $rc
}
check "every patch is pinned in upstream.lock and every pin has a patch" lock_ok
privacy_ok() {
	# No hardware addresses or Apple binaries in what the repository tracks. Files that
	# exist only in the maintainer's checkout are covered by that checkout's own suite.
	! git ls-files -z -- . ':!private' | grep -zvE '^release/.*\.tar$' | xargs -0 grep -IlE '([0-9a-fA-F]{2}:){5}[0-9a-fA-F]{2}' 2>/dev/null | grep . &&
	! git ls-files -- . ':!private' | grep -E '(^|/)(firmware\.bin|[0-9]{4}_01XX\.dat|AppleCamera[A-Za-z]*)$' &&
	! git ls-files -- . ':!private' | grep -E '\.kext(/|$)|firmware[^/]*\.pkg\.tar\.[a-z0-9]+$' || return 1
	# ...and not inside the tracked release tarballs either.
	local t
	for t in $(git ls-files -- 'release/*.tar'); do
		if tar -xOf "$t" | grep -aqE '([0-9a-fA-F]{2}:){5}[0-9a-fA-F]{2}'; then echo "MAC address in $t"; return 1; fi
	done
}
check "tracked files hold no MAC addresses and no Apple firmware" privacy_ok

# --- assembled tree, module build ----------------------------------------------------
if [ -d build/upstream/.git ] || git ls-remote -q "$(awk '$1 == "driver.repo" {print $2}' packaging/upstream.lock)" HEAD >/dev/null 2>&1; then
	check "fetch-upstream.sh assembles the tree from lockfile and patches" packaging/fetch-upstream.sh
	check "assembled tree matches its SOURCES.sha256" bash -c "cd $MOD_DIR && sha256sum --quiet -c SOURCES.sha256"
	wq_src_ok() {
		# 7.2 deprecates system_wq and system_unbound_wq; the driver uses
		# system_dfl_wq. Only irq_work stays on schedule_work (per-CPU).
		! grep -nwE 'system_wq|system_unbound_wq|schedule_delayed_work' "$MOD_DIR"/*.c &&
		! grep -n 'schedule_work(' "$MOD_DIR"/*.c | grep -v 'irq_work'
	}
	check "driver source queues work only on non-deprecated workqueues" wq_src_ok
	tamper_ok() {
		rm -rf "$T/tamper"; cp -a "$MOD_DIR" "$T/tamper"; echo '/* x */' >> "$T/tamper/fthd_hw.c"
		! make -s -C "$T/tamper" KDIR=/nonexistent check 2>/dev/null
	}
	check "the module Makefile refuses a modified source tree" tamper_ok
	KD=/lib/modules/$(uname -r)/build
	if [ -r "$KD/.config" ]; then
		build_ok() {
			rm -rf "$T/kb"; cp -a "$MOD_DIR" "$T/kb"
			# As dkms 3 calls it: KERNELRELEASE on the command line, LLVM=1 for clang kernels.
			local llvm=; grep -qx 'CONFIG_CC_IS_CLANG=y' "$KD/.config" && llvm=LLVM=1
			make -s -C "$T/kb" KERNELRELEASE="$(uname -r)" KVERSION="$(uname -r)" KDIR="$KD" \
				PKGVER="$VERSION" $llvm >/dev/null 2>&1 || return 1
			[ "$(modinfo -F name "$T/kb/macbook91-facetimehd.ko")" = macbook91_facetimehd ] || return 1
			modinfo -F version "$T/kb/macbook91-facetimehd.ko" | grep -qxE "$VERSION\+[0-9a-f]{16}"
		}
		check "module builds for $(uname -r) as dkms 3 calls make, as macbook91_facetimehd $VERSION+<srcid>" build_ok
		wq_ko_ok() { # uses the module build_ok left in $T/kb
			[ -r "$T/kb/macbook91-facetimehd.ko" ] &&
			! nm -u "$T/kb/macbook91-facetimehd.ko" | grep -qwE 'system_wq|system_unbound_wq'
		}
		check "built module references no deprecated workqueue (system_wq, system_unbound_wq)" wq_ko_ok
	else
		blk "no headers for $(uname -r) (module build)"
	fi

	# --- source tarball and install -------------------------------------------------------
	dist_ok() {
		python3 packaging/mkdist.py --allow-dirty --out "$T/d1" >/dev/null &&
		python3 packaging/mkdist.py --allow-dirty --out "$T/d2" >/dev/null &&
		cmp -s "$T/d1/macbook91-facetimehd-$VERSION.tar" "$T/d2/macbook91-facetimehd-$VERSION.tar"
	}
	check "mkdist.py writes byte-identical tarballs" dist_ok
	TAR=$T/d1/macbook91-facetimehd-$VERSION.tar
	content_ok() {
		tar -tf "$TAR" > "$T/list" || return 1
		! grep -E '\.(ko|o)$|firmware\.bin$|_01XX\.dat$|AppleCamera' "$T/list" &&
		grep -q "macbook91-facetimehd-$VERSION/$MOD_DIR/SOURCES.sha256$" "$T/list" &&
		grep -q "macbook91-facetimehd-$VERSION/tools/macbook91-facetimehd-verify$" "$T/list" &&
		grep -q "macbook91-facetimehd-$VERSION/tools/macbook91-facetimehd-kernel-series$" "$T/list" &&
		grep -q "macbook91-facetimehd-$VERSION/tools/macbook91-facetimehd-series.hook$" "$T/list" &&
		grep -q "macbook91-facetimehd-$VERSION/$MOD_DIR/TESTED-SERIES$" "$T/list" &&
		grep -q "macbook91-facetimehd-$VERSION/LICENSE$" "$T/list" &&
		grep -q "macbook91-facetimehd-$VERSION/LICENSES/GPL-2.0-only.txt$" "$T/list" &&
		grep -q "macbook91-facetimehd-$VERSION/LICENSES/GPL-2.0-or-later.txt$" "$T/list" &&
		! grep -q '/packaging/arch/PKGBUILD$' "$T/list"
	}
	check "tarball holds the driver tree, tools and license texts, no binaries, no firmware, no PKGBUILD" content_ok
	install_ok() {
		rm -rf "$T/x" "$T/root"; mkdir -p "$T/x" && tar -xf "$TAR" -C "$T/x" || return 1
		make -s -C "$T/x/macbook91-facetimehd-$VERSION" PREFIX=/usr DESTDIR="$T/root" install || return 1
		local s=$T/root/usr/src/macbook91-facetimehd-$VERSION
		grep -qx "PACKAGE_VERSION=\"$VERSION\"" "$s/dkms.conf" &&
		[ -x "$T/root/usr/bin/macbook91-facetimehd-verify" ] &&
		[ ! -e "$T/root/usr/lib/firmware" ] &&
		[ -r "$T/root/usr/share/doc/macbook91-facetimehd/README.md" ] &&
		(cd "$s" && sha256sum --quiet -c SOURCES.sha256) || return 1
		# The installed note reads the installed list; the hook calls the installed script.
		local k=$T/root/usr/lib/macbook91-facetimehd/kernel-series
		[ -x "$k" ] &&
		grep -qx "SERIES_FILE=/usr/src/macbook91-facetimehd-$VERSION/TESTED-SERIES" "$k" &&
		cmp -s "$s/TESTED-SERIES" packaging/overlay/TESTED-SERIES &&
		[ "$(bash "$k" --list --series-file "$s/TESTED-SERIES")" = "$(bash "$KS" --list --series-file packaging/overlay/TESTED-SERIES)" ] &&
		cmp -s "$T/root/usr/share/libalpm/hooks/71-macbook91-facetimehd-series.hook" tools/macbook91-facetimehd-series.hook
	}
	check "make install from the tarball: DKMS tree with version, tools, series note and hook, doc" install_ok
	if [ -r "dist/macbook91-facetimehd-$VERSION.tar" ] && [ -z "$(git status --porcelain --untracked-files=no)" ]; then
		pin_ok() {
			[ "$(sed -n "s/^sha256sums=('\([0-9a-f]*\)').*/\1/p" packaging/arch/PKGBUILD)" = \
			  "$(sha256sum "$TAR" | cut -d' ' -f1)" ]
		}
		check "PKGBUILD pins the committed tree's tarball" pin_ok
	else
		blk "PKGBUILD pin (needs a committed tree; checked by make arch-pkg)"
	fi
else
	blk "upstream driver not reachable (assembly, build, tarball, install)"
fi

# --- hardware gate (on the test machine only) ---------------------------------------------
blk "hardware: pacman -U of the package, DKMS build for every installed kernel"
blk "hardware: reboot, macbook91-facetimehd-verify PASS (capture, idle power-off)"
blk "hardware: suspend with open camera and hang recovery on the installed module"

echo
echo "$passed passed, $failed failed, $blocked blocked"
[ "$failed" = 0 ]
