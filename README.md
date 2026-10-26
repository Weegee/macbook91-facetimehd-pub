# macbook91-facetimehd

The built-in FaceTime HD camera of the Apple MacBook9,1 (12-inch MacBook,
2016, A1534) on Linux: the
[facetimehd](https://github.com/patjak/facetimehd) driver with this
project's patches, packaged for DKMS, plus a script with which you can
download the Apple firmware the camera needs yourself
(`macbook91-facetimehd-fetch-firmware`).

Developed and tested on one MacBook9,1, the test machine (CachyOS, kernel
7.2.9-cachyos). The package also builds, loads and passes
`macbook91-facetimehd-verify` on the CachyOS LTS kernel
6.18.55-2-cachyos-lts (booted on 2026-10-20 with 20261020.01). Suspend and
resume on 6.18 have not been run. On 7.3.0-4-cachyos DKMS builds the driver
and it loads and probes the camera; image capture and suspend have not been
run on 7.3.

DKMS builds the driver for every installed kernel. The kernel series it has
been tested on are listed in `packaging/overlay/TESTED-SERIES` (6.18 and 7.2);
after a pacman transaction a hook prints a short note for every installed
kernel of another series. If the camera misbehaves on such a kernel, boot the
LTS kernel.

## AI assistance

This project was written by Claude (an AI model by Anthropic): Claude wrote the
project's own code, tests and documentation, and the maintainer gave the directions
and made the decisions. Hardware checks were run on a MacBook9,1 under the
maintainer's direction and count only as far as docs/test-status.json records them as
run; everything else there is marked as not run or carried over. Commits that Claude
contributed to carry a Co-Authored-By trailer; the first public commit is a snapshot
of the earlier private history and carries it too. Read the code before you load a
kernel module or run a script as root.

## What it does

Upstream facetimehd streams on the test machine, but the camera is lost or blocks
the system in situations a laptop runs into daily. On top of upstream commit
c9b063a and its pending PR #355, the patches in `patches/` add:

- **Suspend with the camera open.** S3 and s2idle no longer fail with
  `-EBUSY`; a running stream continues after resume (gap about 2 s in the
  development measurements, 2.99 s once with the installed package, cause
  not verified). In
  s2idle the camera is powered off through the ACPI method `CMPE`, like
  macOS does.
- **Recovery from a hung image processor.** A command timeout or a stream
  that stops delivering frames (2 s watchdog) restarts the chip with a full
  power cycle, which is also what macOS does; a stream continues after about
  3 s. Stopping a stream on a hung chip takes at most 2 s instead of forever.
- **Idle power-off.** The driver keeps ASPM off on the camera link (upstream:
  the chip hangs otherwise), which holds the CPU package in PC3 as long as
  the chip has power. After `idle_poweroff_ms` (default 5000) without a
  stream the chip is powered off: about 0.4 W less package power. The first
  frame after power-off takes about 1.1 s instead of 0.4 s.
- Leak-free, repeatable firmware start and stop; a signal to the streaming
  process is no longer mistaken for a firmware timeout.
- The module version is the package version plus a hash of the sources, so
  `macbook91-facetimehd-verify` can prove which source the loaded module
  came from.
- **Chromium-based browsers find the camera.** The driver lists fixed frame
  sizes (320x240, 424x240, 640x360, 640x480, 848x480 and the native
  848x588) instead of one stepwise range, which Chromium and libwebrtc's
  PipeWire camera skip; before patch 0017 the camera was missing there,
  e.g. in WhatsApp Web calls.

The module is called `macbook91-facetimehd` (`macbook91_facetimehd` in
`lsmod`), so it cannot be confused with an upstream build; the packages
conflict with `facetimehd-dkms` because both bind the same PCI ID.

## Installation (Arch Linux and derivatives)

Install the headers of every kernel you use. Then build and install the driver
package, and get Apple's firmware yourself (step 2).

### 1. Driver

Download `PKGBUILD`, `macbook91-facetimehd-dkms.install`, the source tarball
`macbook91-facetimehd-<version>.tar` and `SHA256SUMS` from the latest release
into one directory, check them and build the package:

```sh
sha256sum -c --ignore-missing SHA256SUMS
makepkg -si          # needs base-devel, dkms and kernel headers
```

`--ignore-missing` skips every file of `SHA256SUMS` that is not in the
directory without a message, so a file you forgot to download does not fail
the check as long as one listed file is present. Look at the output: three
lines must read `OK`: `PKGBUILD`, `macbook91-facetimehd-dkms.install` and the
source tarball. If one of them is missing or reads `FAILED`, do not run
`makepkg`.

From a checkout the same files are in `release/<version>/`. To build from the
source tree (needs network for the upstream driver; a release build needs a
committed tree and the tarball's checksum pinned in `packaging/arch/PKGBUILD`;
`make dist`, which `make arch-pkg` runs, needs a git checkout of the
repository and does not work from an unpacked source tarball):

```sh
make arch-pkg
sudo pacman -U build/arch/macbook91-facetimehd-dkms-<version>-1-x86_64.pkg.tar.zst
```

`make arch-pkg-dev` builds an unreleased working tree (tracked files as they
are on disk) and copies the package to `dist/`. When a release also lists a
ready-built package, install that with `sudo pacman -U` instead. The packages
are not signed. If you maintain your own pacman repository, add the package to
it as usual.

### 2. Firmware: your own download, at your own responsibility

**The camera does not work without Apple's firmware, and this project does not
contain or distribute it.** The firmware is Apple's proprietary software under
Apple's license terms. Whether those terms allow this use has NOT been verified,
and this is not legal advice: read Apple's terms and decide yourself.

If you decide to get it, the driver package installs a script that downloads
it from Apple:

```sh
sudo macbook91-facetimehd-fetch-firmware
```

It asks you to type `yes` first. Then it downloads about 18 MB of Apple's
macOS 10.12.6 combo update from Apple's server (updates.cdn-apple.com) by HTTP
range requests, checks every piece against a pinned SHA256, executes nothing it
downloaded and writes firmware 5.60.0 and the sensor set file 1675 to
`/usr/lib/firmware/facetimehd/`. pacman does not track those two files; remove
them yourself with `sudo rm -r /usr/lib/firmware/facetimehd` when you no longer
want them. The package's install message says the same.

Other distributions, or if the download stops working: the extractor of
patjak/facetimehd-firmware (`make && sudo make install`, commit 60ee212 or
later) installs the same firmware and the sensor set files.
`macbook91-facetimehd-verify` checks the two files by hash either way.

### 3. Load and check

Then load the module and check it:

```sh
sudo modprobe macbook91-facetimehd     # or reboot
macbook91-facetimehd-verify
```

Requires `dkms`, kernel headers matching the running kernel and, for kernels
built with clang (some CachyOS kernels are), the packages `clang`, `lld` and
`llvm`. The module
build refuses to run if the toolchain family does not match the kernel's, or
if its sources do not match `SOURCES.sha256`.

To keep the camera powered while idle:

```sh
echo 'options macbook91_facetimehd idle_poweroff_ms=-1' | sudo tee /etc/modprobe.d/macbook91-facetimehd.conf
```

## Layout

| Path | Content |
|---|---|
| `patches/` | numbered patches on top of upstream c9b063a (0001-0004 = PR #355) |
| `packaging/upstream.lock` | upstream commit, tree hash and the SHA256 of every patch |
| `packaging/fetch-upstream.sh` | assembles `src/macbook91-facetimehd/` from those, refuses any mismatch |
| `packaging/overlay/` | the package's module `Kbuild`, `Makefile` and `dkms.conf`, and `TESTED-SERIES`, the kernel series the driver is tested on |
| `packaging/mkdist.py` | the reproducible source tarball |
| `packaging/arch/` | PKGBUILD, install scriptlet, `.SRCINFO` |
| `release/<version>/` | promoted releases |
| `tools/` | verify tool, firmware fetch script, kernel-series note and its pacman hook (all packaged), development helpers `dev-*.sh` |
| `tests/run-tests.sh` | hermetic tests |
| `docs/` | research, hardware, design, measurements, test status |
| `LICENSE`, `LICENSES/` | license texts: GPL-3.0-or-later (`LICENSE`), GPL-2.0-only and GPL-2.0-or-later (`LICENSES/`); the git repository also keeps the GPL-3.0 text as `LICENSES/GPL-3.0-or-later.txt`, which the source tarball leaves out |

`STRUCTURE.md` holds the rules for these directories.

## Tools

- `macbook91-facetimehd-verify` (packaged): one PASS/FAIL over package,
  firmware, DKMS build, loaded module identity, driver binding, a 60-frame
  capture and idle power-off. Read-only, no root.
- `/usr/lib/macbook91-facetimehd/kernel-series` with the pacman hook
  `71-macbook91-facetimehd-series.hook` (packaged): after a transaction that
  installs or upgrades a kernel or this package, a note for every installed
  kernel whose series is not in `TESTED-SERIES`. It builds and blocks nothing.
- `tools/dev-*.sh`: helpers used while developing, run on the test machine.

## What is proven, and what is not

Measured on the test machine, recorded in `docs/measurements/` and `docs/test-status.json`:
100 open/close cycles, 60 minutes of streaming (108 000 frames, no gap), more
than 30 real suspends in S3 and s2idle with and without a running stream,
injected hangs in streaming and idle, more than 60 power cycles without a
memory leak, v4l2-compliance 57/57.

The packaged installation of 20261013.01 passed its hardware gate (DKMS
build for both installed kernels, `macbook91-facetimehd-verify` PASS after
a reboot).

Releases 20261013.02 (patch 0013), 20261014.01 (patch 0014) and
20261015.01 (patches 0015, 0016) were released without that gate, before this
public repository existed; they are not part of it.
20261014.01 has been booted on the test machine: the module loads, streams, powers the
camera off when idle and the kernel logs no deprecated-workqueue warning.
Hang recovery, `rmmod`, suspend and the new error paths of 0015/0016 have
not been run on hardware with these patches (`docs/test-status.json`:
`hw.patch_0013`, `hw.patch_0014`, `hw.patch_0015_0016`, all NOT_RUN).

Patch 0017 was tested on the test machine with a test module before its release: the
six sizes listed, 300 frames at 640x480 in 11.1 s, every listed size
streams, v4l2-compliance 48/48, Chromium 154 lists the camera and opens it
at 640x480 and 848x588.

Kernel 6.18-LTS: the test machine booted 6.18.55-2-cachyos-lts on 2026-10-20 with
`macbook91-facetimehd-dkms` 20261020.01-1 installed. DKMS had built the
module for that kernel, the loaded module was
`20261020.01+949038441c655353`, and `macbook91-facetimehd-verify` passed
with 0 warnings: firmware hashes match, 60 frames captured in 3008 ms, the
camera powered off after 5000 ms idle. The kernel log of that boot has no
`macbook91_facetimehd` errors. The verify tool's deprecated-workqueue check
only matters on 7.2, which reports that warning; the check cannot fire on
6.18 (`docs/test-status.json`: `hw.lts_kernel`).

Kernel 7.3: the test machine booted 7.3.0-4-cachyos on 2026-10-24 with
`macbook91-facetimehd-dkms` 20261021.01-1 installed. DKMS had built the module
for that kernel, the module loaded and the camera firmware and set file
loaded; the kernel log of that boot has no `macbook91_facetimehd` errors.
`macbook91-facetimehd-verify` (capture, idle power-off) and suspend were not
run on 7.3, so 7.3 is not in `TESTED-SERIES` (`docs/test-status.json`:
`hw.kernel_7_3_probe`, `hw.kernel_7_3_verify`).

Not verified: suspend and resume on 6.18, with and without the camera open
(no suspend happened in that boot; `hw.lts_suspend`), battery effect of the
idle power-off (only CPU package power was measured, on mains),
hibernation, DMABUF streaming and a real (not injected) firmware hang.

## History

The project started on 2026-10-13 as `facetimehd-macbook91` and was renamed
the same day to `macbook91-facetimehd`, to match the naming of its sibling
project macbook91-cs4208. The module was called `facetimehd` until patch 0011. `docs/CHANGELOG.md` lists the
releases.

## Provenance and licensing

The driver is patjak/facetimehd at the commit `packaging/upstream.lock` pins.
The firmware is Apple's; this repository and its packages do not contain it,
and nothing downloads it unless you run `macbook91-facetimehd-fetch-firmware`
yourself. No Apple binaries or Apple code are included. The power and recovery
timing follows the behaviour of Apple's macOS driver; `docs/POWER-RECOVERY.md`
records those findings as facts about registers and timing, and
`docs/HARDWARE.md` describes what the test machine's ACPI tables do, in this
project's own words.

Licenses by path, as SPDX identifiers. `LICENSE` holds the GPL-3.0 text,
`LICENSES/` the other texts.

| Path | License |
|---|---|
| everything not named below: tools, tests, packaging, documentation, data | GPL-3.0-or-later |
| `packaging/overlay/`: the module's `Kbuild`, `Makefile`, `dkms.conf` and `TESTED-SERIES` | GPL-2.0-or-later: GPLv2 section 3 counts the scripts that build and install the module as part of its source |
| `tools/macbook91-facetimehd-fetch-firmware` | GPL-2.0-only: adapted from patjak/facetimehd-firmware (commit 60ee212, GPL-2.0) |
| `patches/`: 0001-0004 by pschatzmann (upstream PR #355), 0005-0017 by this project | GPL-2.0-only, the license of the driver files they change |
| `src/macbook91-facetimehd/` (assembled, not tracked): upstream's `fthd_*` files with the patches applied | GPL-2.0-only; its `Kbuild`, `Makefile`, `dkms.conf` and `TESTED-SERIES` are those from `packaging/overlay/`, GPL-2.0-or-later |
| `docs/diag/`: captured system output (lspci, DMI, wake sources, kernel log) and kernel configuration | not licensed by this project |

Own files with comment syntax start with an `SPDX-License-Identifier` line;
Markdown, JSON and plain-text files carry none and follow this table. The
module is GPL-2.0-only and declares `MODULE_LICENSE("GPL")`; GPL-3.0 code
cannot be compiled into it, and whoever passes on a built module has to
provide its build files under GPLv2 as well. The "or later" label on the
build files in `packaging/overlay/` is this project's own choice for its own
files; it does not widen the license of the upstream driver files next to
them. Releases up to 20261019.01 named
GPL-2.0 as the only license (`LICENSE`, PKGBUILD `GPL-2.0-only`) and keep it.
