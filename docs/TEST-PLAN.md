# TEST-PLAN: measurable quality and stability criteria

As of 2026-10-13 (plan). At that time **no test of this list had been run**, except the compile tests in HARDWARE.md. Current results: `docs/test-status.json` (schema 1 with `id`, `status`, `note`, not the line format planned below) and `docs/measurements/`.

Every test writes raw data to `docs/measurements/<date>-<test>/` (sanitized) and a line to `docs/test-status.json`: `{id, kernel, module_srcversion, firmware_sha256, setfile_sha256, result: PASS|FAIL|NOT_RUN, evidence}`. Global FAIL criterion in every test: new kernel lines with `WARNING:`, `BUG:`, `Oops`, `call trace`, `general protection`, `taint` (except `O`/`E` for out-of-tree/unsigned) since the start of the test.

## Mandatory tests (gate G1)

| ID | Check | Measurement | PASS |
|---|---|---|---|
| T1 Probe | loading, firmware, sensor | `dmesg` | firmware upload ok, `sensor id: 0005 9774`, set file `1675_01XX.dat` loaded, no error line from `facetimehd` |
| T2 Stages | diagnosis on failure | `dmesg` per stage | an error can be attributed to exactly one stage: firmware boot / sensor / set file / channel start |
| T3 Formats/geometry | V4L2 information | `v4l2-ctl --list-formats-ext`, `--get-selection` | YUYV; maximum = native sensor size (848x588 expected, only the measurement counts); `G_SELECTION` = sensor size; test image (circle/grid) without distortion > 2 % |
| T4 Continuous stream | 300 frames 848x588 | `v4l2-ctl --stream-mmap --stream-count=300 --stream-to=/dev/null` with `--verbose` timestamps | 300/300 frames, mean rate 30 ± 1 fps at ≥ 300 lx, no sequence gap, STREAMON to the first frame < 500 ms |
| T5 Image content | content instead of green/black | 10 frames as a raw file, Python/ffmpeg statistics | mean Y 40-220, std. dev. Y > 5, U/V mean 128 ± 20 on a neutral scene, no duplicate frames (hash) |
| T6 PipeWire/browser | desktop path | `pw-cli ls Node` (camera node), `gst-launch-1.0 pipewiresrc ! fakesink num-buffers=300`, Firefox WebRTC test | node present, 300 buffers, Firefox shows a picture for 60 s without a PipeWire crash (`journalctl --user -u pipewire` without SIGSEGV) |

## Stability

| ID | Check | PASS |
|---|---|---|
| T7 Open/close | 100 cycles open → 30 frames → close; plus 20 cycles of STREAMOFF during STREAMON | 100/100, no hang > 5 s, no global FAIL line, `/proc/meminfo` slab growth < 1 MB after the cycles |
| T7b Module reload | 20x `rmmod`/`insmod` | 20/20 successful, device working every time (short T4) |
| T8 Suspend/resume | 10 cycles of S3 (`deep`) each with the camera closed and open; 3 cycles of s2idle each | closed: 10/10, T4 PASS afterwards. Open: suspend must not fail **or** the limitation is documented (upstream: -EBUSY); resume duration +< 1 s compared with baseline T0 |
| T8b Cold boot/reboot | 3 cold boots, 3 warm boots | T1 + T4 PASS each time |
| T9 Battery | C-states/power for 5 min idle with the module loaded, camera closed | package C-state residency (deepest state reached) ≥ 90 % of baseline T0; extra consumption < 0.2 W |
| T10 Endurance run | 60 min stream 848x588 | rate 30 ± 1 fps over the whole time, frame drops < 0.1 %, no global FAIL line, RSS of the consumer stable |

## Image quality (phase 6, measurement instead of judgement)

| ID | Check | Criterion |
|---|---|---|
| Q1 Colour | grey card/neutral, daylight and artificial light | grey deviation U/V ≤ ± 10 after AWB settling (≤ 2 s) |
| Q2 Exposure | bright/dark scene | Y mean 90-160 after ≤ 2 s; no clipped area > 5 % in normal light |
| Q3 Noise | grey area, 100 frames | temporal std. dev. of Y; comparison with/without the set file, not worse with the set file |
| Q4 Sharpness | edge target | MTF50 from a slanted edge (Python), native vs. every scaled output; scaled formats are marked as scaled |
| Q5 Latency | film an LED/clock on the screen | glass-to-glass < 200 ms (guide value, NOT VERIFIED as achievable) |

Hardware limit vs. software: native resolution = sensor size from `G_SELECTION`. Any larger output is scaling and does not count as a gain in resolution.

## Package and kernel change

| ID | Check | PASS |
|---|---|---|
| T11 DKMS | `dkms build/install` for 7.2.9 (clang, `LLVM=1` automatically) and 6.18-LTS (GCC) | both without a warning, `modinfo` shows the right vermagic and source hash |
| T12 Kernel update | simulated update (`dkms autoinstall -k <new>`), boot into the LTS kernel | module present, T1+T4 PASS |
| T13 Installation/rollback | installation, reboot, uninstallation, reboot | after the uninstallation: no `macbook91-facetimehd.ko`, `lspci -k` without a driver, macbook91-cs4208 unchanged (`dkms status`, `macbook91-audio-verify`) |

## Adversarial audit (before publication)

| Area | Method |
|---|---|
| DMA/memory | review of all `dma_*`, SG and S2 IOMMU paths; KASAN kernel; fault injection (`fail_page_alloc`, `failslab`) during buffer allocation |
| Races/deadlocks | lockdep kernel; parallel open/close + suspend (T7 during `rtcwake -m mem`) |
| Error paths | every `goto` path in probe/remove/resume; kmemleak after T7/T7b |
| Firmware/set file | size and header check before the upload; a manipulated file (truncated, zero bytes) may only produce an error, no crash |
| Inputs | V4L2 ioctl fuzzing (`v4l2-compliance -s -f`, syzkaller descriptions for V4L2 if available) |
| Kernel API | build against the current kernel headers of both series + the next RC (`linux-cachyos-rc` or mainline headers) |
| Supply chain | lockfile hashes, no `curl -k`, signed tags, reproducible tarball (two builds, same sha256) |
| Other devices | the driver binds only 14e4:1570; `lspci -k` before/after, audio verification, Wi-Fi/BT unchanged |

Tools: sparse, smatch, coccinelle, `scripts/checkpatch.pl`, clang `scan-build`, KASAN/lockdep/kmemleak kernels, `v4l2-compliance`. Currently not installed on the test machine: sparse, smatch, coccinelle (HARDWARE.md); a build in a temporary directory is planned.
