# T0: baseline without the camera driver (2026-10-13 09:05)

Kernel 7.2.9-1-cachyos, on battery (ADP1 offline, 73 %), no `facetimehd` loaded. Tool: `tools/dev-power-baseline.sh` (root, read-only), 120 s, turbostat interval 10 s, battery values at 1 Hz.

| Value | Mean | Source |
|---|---|---|
| Busy% | 16.6 | turbostat.txt |
| Pkg%pc2 / pc3 / pc6 / pc7 / pc8 / pc9 | 3.08 / 4.02 / 6.22 / 0.08 / 0.00 / 0.00 | turbostat.txt (Pkg%pc10 not offered by the kernel) |
| PkgWatt / CorWatt | 1.10 / 0.32 W | turbostat.txt |
| Battery discharge power | 4.43 W | battery.txt (`current_now × voltage_now`) |
| Camera PMCSR (0x4c) | 0x4008 = D0, NoSoftRst | cam-pmcsr.txt |
| Camera LnkCtl | 0x0042 = ASPM L1, CommClk | cam-lnkctl.txt |
| RP10 LnkCtl | 0x0c42 = ASPM L1 | rp10-lnkctl.txt |

Limitation: the system was not idle (Firefox, this Claude session ≈ 15 % CPU). The values are only good for A/B comparisons under equal conditions (module loaded/unloaded directly one after the other), not as absolute idle values. VERIFIED as a measurement, NOT VERIFIED as representative.

Suspend baseline: no new cycle triggered. From the journal of boot -1 (`suspend-journal-boot-1.txt`): entry to exit 1.90 s, `_PTS` to the NVS save 2.2 ms.

Note: in `suspend-journal-boot-1.txt` the host name was replaced by `testhost`; no other edits.
