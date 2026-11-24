# macbook91-facetimehd

The FaceTime HD camera of the Apple MacBook9,1 (12-inch MacBook, 2016) on Linux: the
[facetimehd](https://github.com/patjak/facetimehd) driver plus this project's patches, packaged
for DKMS on Arch Linux and derivatives. Apple's firmware is not included; a script downloads it
on your request.

## Install

Download `PKGBUILD`, `macbook91-facetimehd-dkms.install`, `macbook91-facetimehd-VERSION.tar` and
`SHA256SUMS` from the [latest release](https://github.com/Weegee/macbook91-facetimehd-pub/releases/latest)
into one new directory. VERSION is the release's version, for example `20261102.01`. Then:

```sh
sha256sum -c --ignore-missing SHA256SUMS
makepkg -si
```

The first command must print three `OK` lines (`PKGBUILD`, the `.install` file, the tar); if one is
missing or reads `FAILED`, do not run `makepkg`. Requirements: `base-devel`, `dkms`, the
headers of every kernel you use and, for clang-built kernels (CachyOS), `clang`, `lld`, `llvm`. Details, other ways to build, removal: [docs/INSTALL.md](docs/INSTALL.md).

## Get the firmware and check

The camera needs Apple's firmware, which is Apple's software under Apple's license terms. Whether
they allow this use has NOT been verified, and this is not legal advice. If you decide to get it:

```sh
sudo macbook91-facetimehd-fetch-firmware
sudo modprobe macbook91-facetimehd
macbook91-facetimehd-verify
```

The first command asks you to type `yes`, downloads about 18 MB from Apple's server, checks every
piece against a pinned SHA256 and writes two files to `/usr/lib/firmware/facetimehd/`. The last
line of the check must read `PASS`:

```text
macbook91-facetimehd verify (7.3.3-1-cachyos)
  PASS  machine is MacBook9,1
  PASS  firmware 5.60.0 and set file 1675 match their pinned SHA256
  PASS  0000:03:00.0 is bound to macbook91_facetimehd
  PASS  kernel log: no macbook91_facetimehd errors this boot

PASS (0 warnings)
```

(Shortened. Output of the test machine with 20261102.01 and `--no-capture`.)

## What the patches add

- **Suspend with the camera open.** S3 and s2idle no longer fail with `-EBUSY`; a running stream
  continues after resume (gap about 2 s).
- **Recovery from a hung image processor.** A command timeout or a stream that stops delivering
  frames (2 s watchdog) restarts the chip with a full power cycle; stopping a stream on a hung
  chip takes at most 2 s instead of forever.
- **Idle power-off.** After `idle_poweroff_ms` (default 5000) without a stream the chip is powered
  off: about 0.4 W less package power; the first frame then takes about 1.1 s instead of 0.4 s.
- **Chromium-based browsers find the camera** (fixed frame sizes instead of one stepwise range).
- Leak-free firmware start and stop; the module version carries a hash of its sources.

The module is called `macbook91-facetimehd` and conflicts with `facetimehd-dkms`, which binds the
same PCI ID.

## Tested, and not

Developed and tested on one MacBook9,1 (CachyOS). The kernel series the driver is tested on are
6.18 (LTS) and 7.2; after a pacman transaction a hook prints a note for every installed kernel of
another series. Kernel 7.3 builds, loads and probes the camera; capture and suspend on it have not
been run. Suspend on 6.18, battery effect, hibernation and DMABUF are not verified. Per release
and per test: [docs/STATUS.md](docs/STATUS.md).

## Read on

| For | Page |
|---|---|
| Install, firmware, remove, the one option | [docs/INSTALL.md](docs/INSTALL.md) |
| What has run on hardware | [docs/STATUS.md](docs/STATUS.md) |
| What changed per release | [docs/CHANGELOG.md](docs/CHANGELOG.md) |
| Licenses by path | [docs/LICENSING.md](docs/LICENSING.md) |
| Directory rules, build, tests | [STRUCTURE.md](STRUCTURE.md) |

Bug reports: <https://github.com/Weegee/macbook91-facetimehd-pub/issues>. Name the kernel
(`uname -r`), the package version (`pacman -Q macbook91-facetimehd-dkms`) and attach the output
of `macbook91-facetimehd-verify`.

This project was written by Claude (an AI model by Anthropic) under the maintainer's direction;
hardware checks count only as far as `docs/test-status.json` records them as run. Read the code
before you load a kernel module or run a script as root. Own files are GPL-3.0-or-later; the
driver and patches are GPL-2.0-only.
