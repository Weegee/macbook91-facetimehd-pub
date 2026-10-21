# OPTIONS: approaches compared

Rating from 1 (poor) to 5 (good). Basis: RESEARCH.md, HARDWARE.md. As of 2026-10-13: at that time no option had been tested on the test machine. What was implemented is B with own patches from 0005 on (option C, `dev_pm_ops` as in F), firmware F1 (an own firmware package, now built from `packaging/firmware/`); since patch 0011 the module name is `macbook91-facetimehd`. Test status: `docs/test-status.json`.

## Driver

| Option | Feasibility | Safety | Stability | Image quality | Effort | Verdict |
|---|---|---|---|---|---|---|
| A. Upstream master c9b063a unchanged | 5 (builds) | 4 | 3 (suspend EBUSY, remove/probe) | 4 (native 848x588) | low | baseline for gate G1; **PipeWire probably broken** (#333) |
| **B. Upstream master + PR #355, pinned** | 5 (builds) | 4 | 3-4 | 4 | low | **recommended starting point** |
| C. B + own MacBook9,1 patches (suspend, warm-up, possibly runtime PM) | 4 | 3-4 (own kernel code, audit needed) | 4-5 | 4-5 | medium | only for errors proven in phase 2 |
| D. AUR facetimehd-dkms 0.7.2 | 4 | 3 | 2-3 (without the crop, buffer and suspend fixes) | 3 | low | only as a comparison, not as the goal |
| E. id1man23 / neron82 file replacement, 640x480 | 3 | 2 | 2 | 2 (cropped) | low | rejected |
| F. Own fork rebuilt on `dev_pm_ops`/runtime PM | 3 | 3 | 5 (goal) | 4 | high | only if C is not enough; an upstream contribution is preferred |
| G. New development | 1 | ? | ? | ? | very high | not justified without evidence |

Reasoning for B: upstream contains all 12-inch corrections (sensor size, crop limits, y1 fix, set-file selection 1675) and builds on both kernels. #355 fixes the only known breakage with PipeWire 1.6.x, is small (3 files, +63/-36) and applies to master without conflicts.

## Firmware

| Option | Download | Evidence | Verdict |
|---|---|---|---|
| **F1. 5.60.0 + 1675 from macOS 10.12.6 via range requests (facetimehd-firmware @ 60ee212)** | ≈ 18 MB | tested on the 10,1, sha256 pinned, official Apple URL | **recommended**, without `curl -k` |
| F2. Boot Camp S2ISP-01.55.00 | 400-540 MB | proven on the 9,1 and 10,1 by third parties | fallback if F1 fails |
| F3. 1.43.0 (AUR facetimehd-firmware) | ≈ 3 MB | "sensor count 0" on the 12-inch model | rejected; conceivable only as a negative control |
| F4. Complete DMG (1.97 GB) with xar/pbzx | 1.97 GB | same content as F1 | only to verify the range method |

## Power and suspend

| Option | Description | Verdict |
|---|---|---|
| P0. Upstream behaviour | suspend -EBUSY with the camera open, otherwise remove/probe | measure as the baseline |
| P1. Allow suspend despite an open camera | stop the stream, return the buffers with an error, keep the `video_device`, restart the ISP after resume | candidate for phase 5 if P0 blocks suspend |
| P2. Runtime PM with `CMPE(0)`/`CMPE(1)` while the camera is closed | battery gain possible, risk "wedged ISP until a cold boot" (#326) | only after a power measurement (T9) and with a fallback |
| P3. Leave the camera's ASPM as it is | the driver switches L0s/L1 off | keep; comment "hangs while streaming" |

## IOMMU

| Option | Verdict |
|---|---|
| Change nothing (DMA remapping is off) | **recommended** |
| `intel_iommu=off` | unnecessary, rejected |
| Optional test with `intel_iommu=on` | only in phase 8, as a robustness check of the SG/S2 IOMMU path, never as a precondition |

## Packaging

| Option | Verdict |
|---|---|
| **Own package `macbook91-facetimehd-dkms` following the cs4208 pattern**: upstream commit + patches via a lockfile, compiler choice from the kernel's `.config`, module name `facetimehd`, DKMS `AUTOINSTALL`, firmware separate | **recommended** |
| AUR facetimehd-dkms + patches via a hook | fragile, no pinning |
| Upstream PR for dkms.conf/Makefile (LLVM detection) | worthwhile in parallel, not blocking |
