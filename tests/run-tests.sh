#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
#
# Hermetic tests for macbook91-facetimehd: no root, no camera, no suspend.
# Network is used only when packaging/fetch-upstream.sh has to clone the
# upstream driver into build/upstream for the first time.
#
# Prints one line per check and a summary "N passed, N failed, N blocked";
# exit status 1 if anything failed, 2 for a usage error. Blocked rows need the
# machine or a missing tool and are named, never counted as passed. The row
# format and the summary line are parsed by the release checks: keep them.
#
set -u

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT" || exit 1
VERSION=$(cat VERSION)
PROG=tests/run-tests.sh

usage_full() {
	cat <<EOF
Usage: $PROG

Runs the hermetic tests of macbook91-facetimehd: no root, no camera, no
suspend. The network is used only when packaging/fetch-upstream.sh has to
clone the upstream driver for the first time. It takes a few minutes.

Example:
  make check                 the same, through the Makefile

Options:
  -h, --help     this help
  -V, --version  version

Output:
  One line per check, marked PASS, FAIL or BLOCKED, then the summary line
  "N passed, N failed, N blocked". A blocked row needs the machine or a
  missing tool; it is never counted as passed.

Exit status:
  0  no check failed
  1  at least one check failed
  2  usage error

Docs and bug reports: https://github.com/Weegee/macbook91-facetimehd-pub
EOF
}
for a in "$@"; do
	case $a in
		-h|--help) usage_full; exit 0 ;;
		-V|--version) echo "$PROG $VERSION"; exit 0 ;;
	esac
done
if [ $# -gt 0 ]; then
	case $1 in -?*) what="unknown option '$1'" ;; *) what="unexpected argument '$1'" ;; esac
	printf '%s: error: %s\nUsage: %s\nExample: make check\nHelp: %s --help\n' "$PROG" "$what" "$PROG" "$PROG" >&2
	exit 2
fi
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
		tools/dev-cam-load.sh tools/dev-cam-unload.sh tools/dev-power-baseline.sh tools/dev-root-diag.sh \
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
	# Without a terminal and without --yes the script downloads nothing: usage error 2 that
	# names --yes. With a terminal it would ask; --no-input also refuses.
	local out rc
	out=$(setsid -w "$FWX" "$T/fw-noask" </dev/null 2>&1); rc=$?
	[ "$rc" = 2 ] && grep -q 'confirmation needed, but there is no terminal' <<<"$out" &&
	grep -q -- '--yes' <<<"$out" && [ ! -e "$T/fw-noask" ] || { echo "no terminal: exit $rc: $out"; return 1; }
	out=$(setsid -w "$FWX" --no-input "$T/fw-noask" </dev/null 2>&1); rc=$?
	[ "$rc" = 2 ] && [ ! -e "$T/fw-noask" ] || { echo "--no-input: exit $rc: $out"; return 1; }
}
check "firmware fetch script refuses to run without an explicit yes (exit 2, names --yes)" fw_ask_ok
fw_note_ok() {
	# The install message says loudly that the firmware is missing and whose terms apply.
	local f=packaging/arch/macbook91-facetimehd-dkms.install
	grep -q "macbook91-facetimehd: warning: the camera does not work yet, Apple's firmware is missing" "$f" &&
	grep -q 'sudo macbook91-facetimehd-fetch-firmware' "$f" &&
	grep -q 'does not contain' "$f" && grep -q 'own account and at your own' "$f"
}
check "install message carries the firmware notice" fw_note_ok
install_hig_ok() {
	# Every message starts with "macbook91-facetimehd: note: " or ": warning: ", follow-up
	# lines are indented, and there is no banner and no shouting (text HIG TYP-1, TXT-8).
	local f=packaging/arch/macbook91-facetimehd-dkms.install out bad
	out=$(bash -c 'source "$1"; post_install' _ "$f" 2>&1) || { echo "$out"; return 1; }
	[ -n "$out" ] || { echo "post_install printed nothing"; return 1; }
	bad=$(grep -vE '^(  |$|macbook91-facetimehd: (note|warning): )' <<<"$out")
	[ -z "$bad" ] || { echo "lines outside the message form:"; echo "$bad"; return 1; }
	! grep -qE '#{5,}|={5,}|IMPORTANT|NOT |WARNING' <<<"$out" || { echo "banner or capitals for emphasis"; return 1; }
}
check "install message: note/warning form, indented follow-up lines, no banner" install_hig_ok
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
		grep -q 'WARN  kernel log: .* 1 workqueue warning naming macbook91_facetimehd'
}
check "verify warns about a workqueue warning naming the module" verify_wq_ok

# --- text interfaces (house text HIG) ------------------------------------------------
# -h/--help: full help on stdout, exit 0, nothing on stderr. -V/--version: one line.
# An unknown option: error line, Usage:, Example:, Help: on stderr, exit 2, nothing on stdout.
ui_ok() { # ui_ok NAME COMMAND...   (UI_NOBAD=1: the command passes unknown options on)
	local name=$1 out rc; shift
	out=$("$@" --help 2>"$T/ui.err"); rc=$?
	[ "$rc" = 0 ] && [ ! -s "$T/ui.err" ] && grep -q '^Usage: ' <<<"$out" &&
	grep -q '^Docs and bug reports: https://github.com/Weegee/macbook91-facetimehd-pub$' <<<"$out" ||
		{ echo "$name --help: exit $rc, or stderr not empty, or no Usage: / docs line"; return 1; }
	out=$("$@" --help --no-such-option 2>/dev/null) && grep -q '^Usage: ' <<<"$out" ||
		{ echo "$name: --help does not win over other arguments"; return 1; }
	out=$("$@" --version 2>"$T/ui.err"); rc=$?
	grep -qE "^[A-Za-z0-9._/-]+( \([a-z0-9-]+\))? $VERSION\$" <<<"$out" && [ "$rc" = 0 ] && [ "$(wc -l <<<"$out")" = 1 ] ||
		{ echo "$name --version: exit $rc, output '$out'"; return 1; }
	[ -z "${UI_NOBAD:-}" ] || return 0
	"$@" --no-such-option >"$T/ui.out" 2>"$T/ui.err" </dev/null; rc=$?
	[ "$rc" = 2 ] && [ ! -s "$T/ui.out" ] && grep -q "^[A-Za-z0-9._ /-]*: error: .*--no-such-option" "$T/ui.err" &&
	grep -q '^Usage: ' "$T/ui.err" && grep -q '^Example: ' "$T/ui.err" && grep -q '^Help: ' "$T/ui.err" ||
		{ echo "$name: unknown option: exit $rc, stdout/stderr not as specified"; sed 's/^/  | /' "$T/ui.err" | head -5; return 1; }
}
check "verify: --help, --version, usage error exit 2" ui_ok verify tools/macbook91-facetimehd-verify
check "kernel-series: --help, --version, usage error exit 2" ui_ok kernel-series bash tools/macbook91-facetimehd-kernel-series
check "fetch-firmware: --help, --version, usage error exit 2" ui_ok fetch-firmware "$FWX"
check "promote-release.sh: --help, --version, usage error exit 2" ui_ok promote-release packaging/promote-release.sh
check "fetch-upstream.sh: --help, --version, usage error exit 2" ui_ok fetch-upstream packaging/fetch-upstream.sh
check "mkdist.py: --help, --version, usage error exit 2" ui_ok mkdist python3 -I packaging/mkdist.py
UI_NOBAD=1 check "make-package.sh: --help and --version (other options are makepkg's)" ui_ok make-package packaging/make-package.sh
for dev in dev-cam-load dev-cam-unload dev-power-baseline dev-root-diag; do
	check "$dev.sh: --help, --version, usage error exit 2 (no root, nothing touched)" ui_ok "$dev" "tools/$dev.sh"
done
check "tests/run-tests.sh: --help, --version, usage error exit 2" ui_ok run-tests tests/run-tests.sh
verify_opt_ok() {
	# A near miss gets a suggestion (HIL-6); the report format is unchanged.
	local err
	err=$(tools/macbook91-facetimehd-verify --nocapture 2>&1 >/dev/null)
	grep -qx 'Did you mean: macbook91-facetimehd-verify --no-capture' <<<"$err"
}
check "verify: a misspelt option names the intended one" verify_opt_ok
mkdist_arg_ok() {
	# --out without a directory is a usage error, not a traceback.
	local err rc
	err=$(python3 -I packaging/mkdist.py --out 2>&1 >/dev/null); rc=$?
	[ "$rc" = 2 ] && grep -q "mkdist.py: error: option '--out' needs a directory" <<<"$err" && ! grep -q Traceback <<<"$err"
}
check "mkdist.py: --out without a value fails with a usage error" mkdist_arg_ok
fw_mock_ok() {
	# The whole path of the fetch script (download, extract, verify, install) against synthetic
	# data: a stub curl serves xz-compressed ranges, a copy of the script pins the hashes of
	# that data. No network, no Apple file.
	local d=$T/fwm out so rc pid
	rm -rf "$d"; mkdir -p "$d/stub" "$d/data" "$d/slow" || return 1
	python3 -I - "$d/data" "$FWX" "$d/fetch" <<'PY' || return 1
import gzip, hashlib, lzma, re, sys
data, src, dst = sys.argv[1:4]
def sha(b): return hashlib.sha256(b).hexdigest()
fw = b"synthetic firmware, not Apple's\n" * 64
gz = gzip.compress(fw, mtime=0)
iface = bytearray(249719 + 507353)
iface[81920:81920 + len(gz)] = gz
setf = (bytes(range(256)) * 71)[:18044]
asst = bytearray(515632)
asst[430080:430080 + len(setf)] = setf
ranges = {"699186570-703316225": bytes(100) + bytes(iface[:249719]),
          "703316242-707986973": bytes(iface[249719:]) + bytes(100),
          "430282546-439105037": bytes(7477241) + bytes(asst) + bytes(1000)}
for rng, blob in ranges.items():
    open(f"{data}/{rng}.xz", "wb").write(lzma.compress(blob))
s = open(src).read()
for pattern, value in ((r"^H_DRV=\w+$", "H_DRV=" + sha(bytes(iface))), (r"^H_ASST=\w+$", "H_ASST=" + sha(bytes(asst))),
                       (r"^H_FW=\w+$", "H_FW=" + sha(fw)), (r"^FW_OFF=81920 FW_LEN=\d+$", f"FW_OFF=81920 FW_LEN={len(gz)}"),
                       (r"^1675 430080 18044 \w+$", "1675 430080 18044 " + sha(setf))):
    s, n = re.subn(pattern, value, s, flags=re.M)
    assert n == 1, pattern
open(dst, "w").write(s)
open(f"{data}/fw.sha", "w").write(sha(fw) + "\n")
PY
	cat > "$d/stub/curl" <<'STUB'
#!/bin/sh
while [ $# -gt 0 ]; do case $1 in -r) r=$2; shift ;; esac; shift; done
[ -r "$MOCKDIR/$r.xz" ] || { echo "curl: (22) The requested URL returned error: 404" >&2; exit 22; }
cat "$MOCKDIR/$r.xz"
STUB
	printf '#!/bin/sh\nexec sleep 30\n' > "$d/slow/curl"; chmod +x "$d/stub/curl" "$d/slow/curl"
	# 1. quiet run: nothing printed, files and modes as promised
	out=$(MOCKDIR=$d/data PATH="$d/stub:$PATH" bash "$d/fetch" --yes -q "$d/out" "$d/keep" 2>&1 </dev/null); rc=$?
	[ "$rc" = 0 ] && [ -z "$out" ] || { echo "-q run: exit $rc, output: $out"; return 1; }
	[ "$(sha256sum < "$d/out/facetimehd/firmware.bin" | cut -d' ' -f1)" = "$(cat "$d/data/fw.sha")" ] &&
	[ -s "$d/out/facetimehd/1675_01XX.dat" ] && [ "$(stat -c %a "$d/out/facetimehd/firmware.bin")" = 644 ] &&
	[ "$(stat -c %a "$d/keep")" = 700 ] && [ "$(ls "$d/keep" | wc -l)" = 2 ] || { echo "files or modes wrong"; return 1; }
	# 2. normal run: stdout stays empty, the result line is on stderr
	so=$(MOCKDIR=$d/data PATH="$d/stub:$PATH" bash "$d/fetch" --yes "$d/out2" 2>"$d/err2" </dev/null); rc=$?
	[ "$rc" = 0 ] && [ -z "$so" ] && grep -q 'verified and written to' "$d/err2" || { echo "normal run: exit $rc, stdout '$so'"; return 1; }
	# 3. a damaged part: error, exit 1, nothing written
	cp -a "$d/data" "$d/bad"; printf x | xz -c > "$d/bad/703316242-707986973.xz"
	out=$(MOCKDIR=$d/bad PATH="$d/stub:$PATH" bash "$d/fetch" --yes "$d/out3" 2>&1 </dev/null); rc=$?
	[ "$rc" = 1 ] && grep -q 'does not match its pinned SHA256' <<<"$out" && [ ! -e "$d/out3" ] ||
		{ echo "damaged part: exit $rc: $out"; return 1; }
	# 4. a failing download: exit 1, the reason and a hint, nothing written
	rm "$d/data/430282546-439105037.xz"
	out=$(MOCKDIR=$d/data PATH="$d/stub:$PATH" bash "$d/fetch" --yes "$d/out5" 2>&1 </dev/null); rc=$?
	[ "$rc" = 1 ] && grep -q 'download from updates.cdn-apple.com failed' <<<"$out" && grep -q -- '--timeout' <<<"$out" &&
	[ ! -e "$d/out5" ] || { echo "failing download: exit $rc: $out"; return 1; }
	# 5. SIGTERM during a stalled download: "cancelled", exit 143, nothing written
	PATH="$d/slow:$PATH" bash "$d/fetch" --yes "$d/out4" >/dev/null 2>"$d/term.err" </dev/null &
	pid=$!; sleep 1; kill -TERM "$pid"; wait "$pid"; rc=$?
	[ "$rc" = 143 ] && grep -q ': cancelled' "$d/term.err" && [ ! -e "$d/out4" ] || { echo "SIGTERM: exit $rc"; return 1; }
}
check "firmware fetch script on synthetic data: -q, stderr, modes, damaged part, failed download, SIGTERM 143" fw_mock_ok

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
		grep -qx "PKGVER=$VERSION" "$k" &&
		grep -qx 'SERIES_FILE=/usr/src/macbook91-facetimehd-$PKGVER/TESTED-SERIES' "$k" &&
		[ "$(bash "$k" --version)" = "macbook91-facetimehd-kernel-series (macbook91-facetimehd-dkms) $VERSION" ] &&
		[ "$("$T/root/usr/bin/macbook91-facetimehd-verify" --version)" = "macbook91-facetimehd-verify $VERSION" ] &&
		[ "$("$T/root/usr/bin/macbook91-facetimehd-fetch-firmware" --version)" = "macbook91-facetimehd-fetch-firmware $VERSION" ] &&
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
