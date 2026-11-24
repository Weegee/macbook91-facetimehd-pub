# Changelog

Versions have the form YYYYMMDD.NN (release date, NN counts releases that day). The release tag
is v<version>. Entries say what changes for users. Commit hashes before 20261021.01 belong to the
maintainer's private history. Runtime tests per release: `docs/test-status.json`.

## 20261109.01 (2026-11-09)

Documentation only; no driver change (same upstream commit c9b063a and patches 0001-0017 as
20261102.01). Not run on hardware.

- README: numbered install steps with the expected checksum output, a check after the install,
  a "Remove" section, usage with the output of `macbook91-facetimehd-verify`, the one module
  option and how to report bugs.

## 20261102.01 (2026-11-02)

No driver change.

- The pacman install message on an upgrade is one short note: old and new version, that the
  loaded module is replaced at the next boot or module reload, the warnings that make the DKMS
  build fail, and four lines when Apple's firmware is missing. A first installation is unchanged.
- `kernel-series --hook`: the first line of the note no longer ends with a period.

## 20261026.02 (2026-10-26)

No driver change. **Incompatible for scripts:** `macbook91-facetimehd-fetch-firmware` writes its
notice and question to stderr (it wrote the notice to stdout) and, without a terminal and without
`--yes`, stops with exit status 2 (it was 1); pass `--yes` in scripts. `tools/dev-cam-load.sh`
and `dev-cam-unload.sh` exit with 1 when insmod or rmmod failed (they exited with 0).

- Every command answers `--help` and `--version`. A wrong argument is a usage error: exit status
  2, the error, a `Usage:` and an `Example:` line, and a near miss names the intended option.
  Ctrl+C and SIGTERM end the tools with `NAME: cancelled` (exit 130 and 143).
- `macbook91-facetimehd-fetch-firmware` gets `-y/--yes`, `--no-input`, `-q/--quiet`,
  `-o/--output DIR`, `--keep DIR` and `--timeout SEC`; a stalled download ends after 30 s
  (there was no limit); progress goes to stderr, stdout stays empty.
- `macbook91-facetimehd-verify`: the report format is unchanged; plurals are right
  (`PASS (1 warning)`).
- All `tools/dev-*.sh` refuse to run without root instead of failing halfway.

## 20261026.01 (2026-10-26)

No driver change.

- New: the DKMS tree lists the kernel series the driver is tested on (`TESTED-SERIES`: 6.18 and
  7.2), and a pacman hook (`71-macbook91-facetimehd-series.hook`) prints a note for every
  installed kernel of another series after a kernel or package transaction. It builds and blocks
  nothing; DKMS still builds for every kernel.
- Kernel 7.3: DKMS built the module and it probed the camera; capture, idle power-off and
  suspend were not run, so 7.3 is not in the list.

## 20261021.01 (2026-10-21)

First release prepared for a public repository. No driver logic change (module source identity
949038441c655353 unchanged).

**Incompatible:** the driver package no longer depends on a firmware package and downloads
nothing during a build. After the install, run `sudo macbook91-facetimehd-fetch-firmware` once,
on your own responsibility. The four development helpers are now `tools/dev-*.sh`.

- `macbook91-facetimehd-fetch-firmware` asks for an explicit `yes`, downloads Apple's update
  from Apple's server, checks four pinned hashes and writes the firmware to
  `/usr/lib/firmware/facetimehd/`. The install message says so whenever the firmware is missing.
- `macbook91-facetimehd-verify` checks the two firmware files by hash and names the fetch
  command when they are missing.
- Licenses: own files GPL-3.0-or-later, the module's build files GPL-2.0-or-later, driver and
  patches GPL-2.0-only (`docs/LICENSING.md`). The decompiled ACPI excerpts are no longer in the
  repository; `docs/entwicklung/HARDWARE.md` describes those methods in the project's own words.
- `docs/entwicklung/HARDWARE.md` corrected: the wait for the link after `CMPE(1)` is up to 1 s, not 10 s.
- Not run on hardware; carried over from 20261020.02 because the driver sources are identical.

## 20261020.02 (2026-10-20)

Documentation only, no driver change. The README states that 6.18.55-2-cachyos-lts was booted
with 20261020.01: `macbook91-facetimehd-verify` PASS with 0 warnings, 60 frames in 3008 ms,
power-off after 5000 ms idle. Suspend on 6.18 was not run.

## 20261020.01 (2026-10-20)

No driver change.

- Licenses: own files GPL-3.0-or-later with an SPDX line; the module's `Kbuild`, `Makefile` and
  `dkms.conf` GPL-2.0-or-later (GPLv2 section 3); driver and patches GPL-2.0-only. `LICENSES/`
  holds the texts.
- The README says that 20261015.01 also went out without the hardware gate. The install
  scriptlet's rollback hint uses sudo. The documentation is in English.

## 20261019.01 (2026-10-19)

- 0017: the driver lists fixed frame sizes (320x240, 424x240, 640x360, 640x480, 848x480 and the
  native 848x588) instead of one stepwise range. Chromium and libwebrtc's PipeWire camera skip
  stepwise sizes, so the camera was missing in Chromium-based browsers and WhatsApp Web calls.
  Tested with a test module.

## 20261015.01 (2026-10-15)

- 0015: `VIDIOC_S_FMT` returns EBUSY while the queue has buffers (it changed the format under a
  running stream, and the next restart made the firmware write past the buffers). Buffers smaller
  than a frame are refused.
- 0016: writing the debugfs file `debug` while the camera is off returns EIO instead of crashing
  the kernel; the frame watchdog stops after the interrupt work, and remove cancels it.

## 20261014.01 (2026-10-14)

- 0014: idle power-off, frame watchdog and recovery run on `system_dfl_wq` instead of
  `system_wq`, which kernel 7.2 reports as deprecated.
- `macbook91-facetimehd-verify` warns about kernel workqueue warnings that name the module.
- `dkms.conf` no longer sets `CLEAN`, which dkms 3 reports as deprecated on every build.

## 20261013.02 (2026-10-13)

- 0013: remove and shutdown no longer leave a recovery queued when stopping a hung firmware times
  out (use-after-free); STREAMON during remove is refused; a set file too large for its memory
  region is skipped like a missing one instead of crashing. On hardware NOT VERIFIED.

## 20261013.01 (2026-10-13)

First release: package `macbook91-facetimehd-dkms`, module `macbook91-facetimehd`. Driver:
patjak/facetimehd c9b063a with

- 0001-0004 upstream PR #355 (IOMMU buffers inside a page, partial buffer setup, no endless wait
  for buffers)
- 0005-0006 leak-free, repeatable firmware start and stop; a signal is no longer a firmware
  timeout
- 0007-0008 power cycle through ACPI `CMPE`, recovery work, a stream survives S3 and s2idle
- 0009 hang detection: command timeout, 2 s frame watchdog, bounded `stop_streaming`
- 0010 idle power-off after `idle_poweroff_ms` (default 5000)
- 0011-0012 debugfs directory named after the module; module version = package version + source
  hash

DKMS tree checked against `SOURCES.sha256` before every build. Measurements:
`docs/entwicklung/measurements/2026-10-13-T0` and `2026-10-13-phase2`.
