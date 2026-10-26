# Changelog

Versions have the form YYYYMMDD.NN (release date, NN counts releases that
day). The release tag is v<version>.

## 20261026.01

Kernel series note. No driver change.

- Driver: the same upstream commit c9b063a and patches 0001-0017 as
  20261021.01; module source identity 949038441c655353 unchanged.
- The DKMS tree carries `TESTED-SERIES` (from `packaging/overlay/`): the
  kernel series on which `macbook91-facetimehd-verify` passed on the test
  machine, 6.18 and 7.2. DKMS still builds the driver for every kernel;
  `dkms.conf` sets no `BUILD_EXCLUSIVE_KERNEL`.
- New pacman hook `71-macbook91-facetimehd-series.hook` with
  `/usr/lib/macbook91-facetimehd/kernel-series`, the only reader of that list:
  after a transaction that installs or upgrades a kernel or this package it
  prints a two-line note for every installed kernel of a series not in the
  list, with the tested series and the LTS kernel as the fallback. It builds
  and blocks nothing and never fails the transaction. A series joins the list
  in a later release, after a verify PASS on it.
- Kernel 7.3: on 7.3.0-4-cachyos DKMS built 20261021.01, the module loaded and
  probed the camera (firmware and set file loaded, no driver errors in that
  boot). Capture, idle power-off and suspend were not run on 7.3, so 7.3 is
  not in the list and the hook names 7.3 kernels.
- Tests: hermetic tests of the list, the note on a simulated kernel tree with
  tested and untested series, the exit codes, the hook file and the installed
  paths.

## 20261021.01

First release prepared for a public repository. Documentation, licensing and
packaging only, no driver logic change.

Commit hashes named in entries up to 20261021.01 belong to the maintainer's private history and do not exist in the public repository.

- Driver: the same upstream commit c9b063a and patches 0001-0017 as
  20261020.02. Module source identity 949038441c655353 and `SOURCES.sha256`
  are unchanged, and the unpacked module trees of the two source tarballs
  are identical. The tarball differs from 20261020.02 in README.md, the
  Makefile (`make install` also installs the firmware fetch script), VERSION,
  `tools/macbook91-facetimehd-verify` and the new
  `tools/macbook91-facetimehd-fetch-firmware`.
- Firmware: the package no longer depends on a firmware package and nothing
  downloads Apple's firmware during a build. The driver package installs
  `macbook91-facetimehd-fetch-firmware`; the user runs it after the install,
  on their own responsibility (Apple's license terms were not verified). It
  asks for an explicit `yes`, downloads Apple's update from Apple's server,
  checks four pinned hashes and writes the firmware to
  `/usr/lib/firmware/facetimehd/`. The install message says so prominently
  whenever the firmware is missing. `macbook91-facetimehd-verify` no longer
  looks for a firmware package; it checks the two files by hash and names the
  fetch command when they are missing. The separate firmware package recipe
  (`packaging/firmware/`) was removed. The extraction is the one a real
  `makepkg` build of that recipe ran once on 2026-10-20 (both files equal to
  the installed ones by `cmp`). No Apple firmware, other Apple binary or
  Apple code is in the repository, the tarball or a release.
- ACPI: the decompiled excerpts of the test machine's ACPI tables (Apple's
  code) are no longer part of the repository; `docs/HARDWARE.md` describes
  what those methods do in this project's own words.
- `docs/HARDWARE.md` corrected: the wait for the link to come up after
  `CMPE(1)` is up to 1 s, polled every 10 ms (it said up to 10 s), as the
  decompiled DSDT shows. `STRUCTURE.md` and `docs/FIRMWARE.md` say that no
  Apple firmware or other Apple binary is tracked or released. The README says that the private releases 20261013.02 to
  20261015.01 were released without the hardware gate, not published.
- Patches 0007-0016: header text only (session links and a host name
  removed), hunks unchanged; the ten patch hashes in `packaging/upstream.lock`
  were regenerated.
- Licenses: `LICENSES/GPL-3.0-or-later.txt` added; an unused MIT text
  removed; the README license table lists the files of this repository. The
  extractor is GPL-2.0-only, as it is adapted from the upstream firmware
  project.
- Text: install instructions that build the package from the release files
  or the source tree, with a checksum step that lists the lines that must
  read OK and the note that `make dist` needs a git checkout, an
  AI-assistance note, neutral wording in the documentation, the four
  host-named development helpers renamed to `tools/dev-*.sh`, agent working
  notes no longer part of this repository.
  "No Apple code is copied" is replaced by an accurate statement: no Apple
  binaries are included, and short excerpts of Apple's ACPI tables are
  quoted in `docs/diag/` for interoperability research.
- Release directory: only `release/20261021.01/` is kept. Earlier release
  directories are not part of this repository.
- Runtime of the 20261021.01 build: not run. Carried over from 20261020.02
  and 20261020.01, because the driver sources are byte-identical (see
  `docs/test-status.json`, `hw.release_20261021_01`).

## 20261020.02

- Documentation only, no driver change: the same upstream commit and
  patches 0001-0017 as 20261020.01, module source identity
  949038441c655353 unchanged. Compared with 20261020.01 the source tarball
  differs only in README.md and VERSION.
- The packaged README states the 6.18 state. It said that the module builds
  for 6.18-cachyos-lts and that kernel had not been booted with it. The
  maintainer booted 6.18.55-2-cachyos-lts on the test machine on 2026-10-20 with
  20261020.01: `macbook91-facetimehd-verify` PASS with 0 warnings, firmware
  hashes match, 60 frames in 3008 ms, camera powered off after 5000 ms
  idle, no module errors in that boot's kernel log. Suspend and resume on
  6.18, with and without the camera open, were not run and are listed as
  not verified. The verify tool's deprecated-workqueue check cannot fire on
  6.18.
- Runtime of the 20261020.02 build itself: not run. The evidence of
  20261020.01 carries over because the module source is identical.

## 20261020.01

- No driver change: the same upstream commit and patches 0001-0017 as
  20261019.01. The packaged README says that 20261015.01 also went out
  without the hardware gate and that hang recovery, rmmod, suspend and the
  error paths of 0015/0016 have not been run on hardware with these
  patches. The install scriptlet's rollback hint uses sudo.
- License: this project's own files (tools, tests, packaging, documentation,
  data) are GPL-3.0-or-later, and `LICENSE` holds the GPL-3.0 text. The
  module's Kbuild, Makefile and dkms.conf are GPL-2.0-or-later, because
  GPLv2 section 3 counts the scripts that build and install a module as part
  of its source. The driver and patches 0001-0017 stay GPL-2.0-only;
  `LICENSES/` holds the license texts. Own files
  with comment syntax start with an SPDX-License-Identifier line; README.md
  maps every path. The PKGBUILD declares all three GPL identifiers, the
  source tarball adds the two GPL-2.0 texts, and a test checks the license
  texts and SPDX lines. The driver's source files are unchanged.
- Language: the documentation was translated from German
  into English; facts, dates and numbers are unchanged, and claims are
  tagged VERIFIED / NOT VERIFIED / REFUTED. Captured German-locale output,
  the sealed release records and the git history stay as they were. No
  packaged file changed.

## 20261019.01

- 0017 VIDIOC_ENUM_FRAMESIZES lists fixed sizes (320x240, 424x240,
  640x360, 640x480, 848x480, 1280x720 where they fit the sensor, and the
  native size last, 848x588 on the MacBook9,1) instead of one stepwise
  range. Chromium and libwebrtc's PipeWire camera skip stepwise sizes and
  then drop the camera, so it was missing in Chromium-based browsers and
  WhatsApp Web calls reported no camera. Tested on the test machine with a test module.

## 20261015.01

- 0015 VIDIOC_S_FMT returns EBUSY while the queue has buffers; it used
  to change the format under a running stream, and the next stream
  restart (recovery, resume) made the firmware write past the buffers.
  Buffers smaller than a frame are refused.
- 0016 writing to the debugfs file `debug` while the camera is powered
  off returns EIO instead of crashing the kernel; the teardown stops the
  frame watchdog after the interrupt work, and remove cancels it.
- README and the project state say what the hardware has verified of
  20261013.02 and 20261014.01; the test for deprecated workqueues also
  rejects system_unbound_wq.

## 20261014.01

- 0014 the idle power-off, frame watchdog and recovery are queued on
  system_dfl_wq (system_unbound_wq before 6.17) instead of system_wq,
  which kernel 7.2 reports as deprecated once per boot. Builds for
  7.2.9-2 and 6.18.55-2-LTS.
- macbook91-facetimehd-verify warns about kernel workqueue warnings that
  name the module (they start with `workqueue:`, not with the module name).
- dkms.conf no longer sets CLEAN, which dkms 3 ignores and reports as
  deprecated on every build.

## 20261013.02

- 0013 remove/shutdown no longer leaves a recovery queued when stopping a
  hung firmware times out (use-after-free), STREAMON during remove is
  refused, and a set file too large for its memory region is skipped like a
  missing one instead of crashing. Builds for 7.2.9-2 and 6.18.55-2-LTS;
  on hardware NOT VERIFIED.

## 20261013.01

First release. Package `macbook91-facetimehd-dkms`; it depends on
`macbook91-facetimehd-firmware`. At that time the firmware files were held in
a separate repository, independent of Apple's servers. The firmware package is
now built from `packaging/firmware/`, which downloads the files from Apple
at build time and checks pinned hashes (see README.md).

Driver: patjak/facetimehd c9b063a with patches

- 0001-0004 upstream PR #355 (IOMMU buffers inside a page, partial buffer
  setup, no endless wait for buffers, comment)
- 0005 isp_init/isp_uninit leak-free and repeatable
- 0006 a signal is no longer a firmware timeout
- 0007 hardware bring-up separated from probe, power cycle through ACPI
  CMPE, recovery work, buffers survive a restart, debugfs `state`/`recover`
- 0008 dev_pm_ops: a stream survives S3 and s2idle; s2idle powers the camera
  off; asynchronous resume
- 0009 hang detection: command timeout, 2 s frame watchdog, bounded
  stop_streaming, debugfs `inject_hang`
- 0010 idle power-off after `idle_poweroff_ms` (default 5000)
- 0011 debugfs directory named after the module
- 0012 module version = package version + source hash

Packaging: module `macbook91-facetimehd` (lsmod `macbook91_facetimehd`),
DKMS tree checked against SOURCES.sha256 before every build, objects in
`Kbuild` so that dkms 3 (which sets KERNELRELEASE) builds it, compiler family
taken from the target kernel, `macbook91-facetimehd-verify` (checks the
firmware against pinned hashes).

Measurements: docs/measurements/2026-10-13-T0 and 2026-10-13-phase2.
