# FIRMWARE: provenance and verification

Extracted on 2026-10-13 on the test machine. No Apple binary data in this repository.

## Source

- URL: `https://updates.cdn-apple.com/2019/cert/041-90765-20191011-837e856d-b522-4865-b64c-641048ed77c4/macOSUpdCombo10.12.6.dmg` (official Apple CDN, TLS verified, `curl --proto =https`, without `-k`)
- Range downloads (pbzx chunks, each a complete xz stream): 699186570-703316225 (4 129 656 B), 703316242-707986973 (4 670 732 B), 430282546-439105037 (8 822 492 B). Total 17.6 MB.
- Tools: curl 8.22.0, xz 5.8.3, gzip 1.15, extractor patjak/facetimehd-firmware 60ee212.

## Results (all VERIFIED by sha256 against the values pinned in the extractor)

| Artifact | Size | sha256 |
|---|---|---|
| AppleCameraInterface (kext, Mach-O x86_64) | 757 072 | e959244db1e0561f6d5590c8e5000a36816c592e2820bafe89af0bea75556aca |
| AppleCameraAssistant (Mach-O x86_64) | 515 632 | af6a9de00472657e925f546753c818f9e33636030892b14ca96a1b4817ea58c7 |
| firmware.bin 5.60.0 (gzip @81920, 602903 B) | 1 417 220 | 240ef2e991f1d089d8228ce11d92b66bfa4b3d7289ec4fee228b64a713024330 |
| 1675_01XX.dat (@430080 in the Assistant) | 18 044 | b7a38aef2755721bb28c92d84a15654b17e9fb3b0a0f088a384a981fc8fe16d6 |

The other ten set files were extracted as well and their hashes checked too; according to the driver code the test machine needs only 1675 (sensor 0005/9774). VERIFIED on the test machine: every bring-up reports `loaded set file facetimehd/1675_01XX.dat`, and only sensor 0x9774 with id0 5 selects this file (see RESEARCH.md).

## Storage

- Test path: `~/.local/share/macbook91-facetimehd/firmware-root/facetimehd/` (for `firmware_class.path`, nothing is written to `/usr/lib/firmware`).
- Kext and Assistant for reverse engineering: kept locally by the maintainer, never tracked or published.

## Reproduction

The fetch script `tools/macbook91-facetimehd-fetch-firmware` is part of this repository and of the driver package (adapted from patjak/facetimehd-firmware, GPL-2.0-only). No package build downloads anything from Apple: the user runs `sudo macbook91-facetimehd-fetch-firmware` after the install, on their own responsibility, as the install message and the README say. It asks for an explicit `yes`, downloads the same three ranges from Apple's server, checks all four hashes above and writes `facetimehd/{firmware.bin,1675_01XX.dat}` to `/usr/lib/firmware` (or to a directory given as its argument). No Apple firmware, other Apple binary or Apple code is tracked or released.

Until 20261021.01 (not released) the repository carried a separate firmware package recipe that ran this download at package build time; it was removed so that only the user starts the download.

Checked on 2026-10-20 with that earlier recipe, which ran the same script: a real `makepkg` build as a normal user downloaded 17.6 MB (three HTTP range requests, TLS) and produced both files bit for bit identical (`cmp`) to the files extracted on 2026-10-13 and to the pins in `tools/macbook91-facetimehd-verify`. VERIFIED. A build in a clean chroot was NOT VERIFIED, Apple's license terms for these files were NOT VERIFIED (this is not legal advice), and the package was not installed from that build. The hardware runs in `docs/test-status.json` used the same two files, `firmware.bin` and `1675_01XX.dat` (same sha256 as the pins), but installed by the maintainer's own earlier firmware package, which carries 13 files. Files written by the script were checked by `cmp` only; the camera has not run from them.
