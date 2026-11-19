# Install, firmware, remove

For Arch Linux and derivatives. Needs `base-devel`, `dkms`, the headers of every kernel you use
and, for kernels built with clang (some CachyOS kernels), `clang`, `lld` and `llvm`. The module
build refuses to run if the toolchain family does not match the kernel's or if its sources do not
match `SOURCES.sha256`.

## Install the driver package

1. Download `PKGBUILD`, `macbook91-facetimehd-dkms.install`, `macbook91-facetimehd-VERSION.tar`
   and `SHA256SUMS` from the [latest release](https://github.com/Weegee/macbook91-facetimehd-pub/releases/latest)
   into one new directory.
2. Check the files in that directory. The output must list three files, each `OK`:

   ```sh
   sha256sum -c --ignore-missing SHA256SUMS
   ```

   `--ignore-missing` skips files you did not download without a message, so the exit status alone
   does not show that all three were checked. If one is missing or reads `FAILED`, stop here.
3. Build and install:

   ```sh
   makepkg -si
   ```

4. Check that DKMS built the module for every installed kernel. Each line must end with
   `installed`:

   ```sh
   dkms status macbook91-facetimehd
   ```

Checked on 2026-11-09 on the files of release 20261102.01: step 2 and the `dkms status` command.
Not run for this revision of the text: step 3, the firmware download, loading the module, removal.

To build from a git checkout instead (needs network for the upstream driver):

```sh
make arch-pkg
sudo pacman -U build/arch/macbook91-facetimehd-dkms-VERSION-1-x86_64.pkg.tar.zst
```

`make arch-pkg-dev` builds an unreleased working tree and copies the package to `dist/`. The
packages are not signed.

## Get the firmware

The camera does not work without Apple's firmware. This project neither contains nor distributes
it. It is Apple's proprietary software; whether its license terms allow this use has NOT been
verified, and this is not legal advice. If you decide to get it:

```sh
sudo macbook91-facetimehd-fetch-firmware
```

The script asks you to type `yes`. Without a terminal it stops with exit status 2 and tells you to
pass `--yes`, which says you have read Apple's terms. It downloads about 18 MB of Apple's macOS
10.12.6 combo update from `updates.cdn-apple.com` by HTTP range requests, checks every piece
against a pinned SHA256, executes nothing it downloaded and writes firmware 5.60.0 and the sensor
set file 1675 to `/usr/lib/firmware/facetimehd/`. Nothing is written unless every piece matches.
`-q` silences progress, `-o DIR` writes to `DIR/facetimehd`, `--help` lists the rest.

Other distributions, or if the download stops working: the extractor of
patjak/facetimehd-firmware (`make && sudo make install`, commit 60ee212 or later) installs the
same files.

## Load and check

1. Load the module, or reboot:

   ```sh
   sudo modprobe macbook91-facetimehd
   ```

2. Run the check. It reads and changes nothing and needs no root; run it after every kernel
   update too. The last line must read `PASS`, with or without warnings:

   ```sh
   macbook91-facetimehd-verify
   ```

`--no-capture` skips the 60-frame capture and the idle power-off check.

## The option

`idle_poweroff_ms`: milliseconds without a stream after which the camera is powered off (default
5000, `-1` never). To keep the camera powered while idle, then reboot or reload the module:

```sh
echo 'options macbook91_facetimehd idle_poweroff_ms=-1' | sudo tee /etc/modprobe.d/macbook91-facetimehd.conf
```

## Remove

Remove the package, then reboot; the loaded module stays until then:

```sh
sudo pacman -R macbook91-facetimehd-dkms
```

Remove the firmware (only if you fetched it) and the option file (only if you created it):

```sh
sudo rm -r /usr/lib/firmware/facetimehd
sudo rm /etc/modprobe.d/macbook91-facetimehd.conf
```

## Other tools

`/usr/lib/macbook91-facetimehd/kernel-series` with the pacman hook
`71-macbook91-facetimehd-series.hook`: after a transaction that installs a kernel or this package,
a note for every installed kernel whose series is not in `TESTED-SERIES`. It builds and blocks
nothing.
