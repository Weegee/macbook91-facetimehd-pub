# Licenses by path

SPDX identifiers. `LICENSE` holds the GPL-3.0 text, `LICENSES/` the other texts. Own files with
comment syntax start with an `SPDX-License-Identifier` line; Markdown, JSON and plain-text files
carry none and follow this table.

| Path | License |
|---|---|
| everything not named below: tools, tests, packaging, documentation, data | GPL-3.0-or-later |
| `packaging/overlay/`: the module's `Kbuild`, `Makefile`, `dkms.conf` and `TESTED-SERIES` | GPL-2.0-or-later: GPLv2 section 3 counts the scripts that build and install the module as part of its source |
| `tools/macbook91-facetimehd-fetch-firmware` | GPL-2.0-only: adapted from patjak/facetimehd-firmware (commit 60ee212, GPL-2.0) |
| `patches/`: 0001-0004 by pschatzmann (upstream PR #355), 0005-0017 by this project | GPL-2.0-only, the license of the driver files they change |
| `src/macbook91-facetimehd/` (assembled, not tracked): upstream's `fthd_*` files with the patches applied | GPL-2.0-only; its `Kbuild`, `Makefile`, `dkms.conf` and `TESTED-SERIES` are those from `packaging/overlay/` |
| `docs/diag/`: captured system output and kernel configuration | not licensed by this project |

The module is GPL-2.0-only and declares `MODULE_LICENSE("GPL")`; GPL-3.0 code cannot be compiled
into it, and whoever passes on a built module has to provide its build files under GPLv2 as well.
The "or later" label on `packaging/overlay/` is this project's choice for its own files and does
not widen the license of the upstream files next to them. Releases up to 20261019.01 named GPL-2.0
as the only license and keep it.

## Provenance

The driver is patjak/facetimehd at the commit `packaging/upstream.lock` pins. The firmware is
Apple's; this repository and its packages do not contain it. No Apple binaries or Apple code are
included. The power and recovery timing follows the behaviour of Apple's macOS driver;
`docs/POWER-RECOVERY.md` records it as facts about registers and timing, and `docs/HARDWARE.md`
describes in this project's own words what the test machine's ACPI tables do.
