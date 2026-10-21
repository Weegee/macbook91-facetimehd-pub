# RESEARCH: Linux support for the MacBook9,1 camera

As of 2026-10-13. Sources cloned locally (in a temporary directory, not in the repository): patjak/facetimehd @ c9b063a (2026-10-05), patjak/facetimehd-firmware @ 60ee212 (2026-08-19), id1man23/macbook12-camera-fix @ da2e342, thomas-shirley/macbook8.1-camera @ 9906d94, neron82/macbook10-1-facetimehd-linux @ 61a875f, the macbook91-cs4208 audio driver by the same author @ e61a66c. Issues/PRs via `gh`.

Marking: **VERIFIED** = seen in code, a primary source or a measurement. **NOT VERIFIED** = plausible, without evidence. **REFUTED** = counter-evidence exists.

## 1. Key result

1. Upstream `patjak/facetimehd` master supports the 12-inch MacBooks since PR #327 (merged 2026-06-26): the sensor size is read from the firmware instead of being fixed at 1280x720 (commit 98b55fd). VERIFIED.
2. A third party reports the MacBook9,1 as working: kernel 7.1.5-arch, firmware S2ISP-01.55.00 (Boot Camp), sensor 0005/9774, set file `1675_01XX.dat`, no special CMPE handling, only bdc_pci blacklisted ([#326, comment 2026-08-10](https://github.com/patjak/facetimehd/issues/326#issuecomment-5236507227)). VERIFIED as a statement, NOT VERIFIED on the maintainer's MacBook9,1 (the test machine).
3. The AUR firmware `facetimehd-firmware` 1:1.43_5-2 is unsuitable for the 12-inch models ("sensor count: 0", #196/#326 for MacBook10,1). NOT VERIFIED for MacBook9,1, but the same sensor.
4. `facetimehd-firmware` @ 60ee212 by default extracts firmware 5.60.0 from macOS 10.12.6 and all 11 set files including 1675 via HTTP range requests (~18 MB). According to PR #12 tested only on MacBook10,1. VERIFIED (script/PR), NOT VERIFIED on MacBook9,1.
5. Upstream master breaks PipeWire since #333 (USERPTR removed, buffers that are not page-aligned refused). Open fix: PR #355. Affected: PipeWire ≥ 1.2.7, the test machine has 1.6.9. VERIFIED (PR text with strace), NOT VERIFIED on the test machine.
6. Upstream compiles on the test machine against 7.2.9 (clang/ThinLTO, `LLVM=1`) and 6.18-LTS (GCC) without a warning; so does master+#355. VERIFIED (compile test, not loaded).

## 2. The upstream driver in detail (c9b063a)

### Sensor and set file (fthd_isp.c:519-603)
- Selection by `sensor_id1`/`sensor_id0` from CH_INFO_GET (fthd_isp.c:643-644). `0x9774` + `id0==5` → `facetimehd/1675_01XX.dat` (fthd_isp.c:569-579). VERIFIED (read myself).
- DMI only for the MacBookAir branch of 0x9770. "MacBook9,1" appears nowhere in the code. VERIFIED.
- A missing set file is not fatal: the driver keeps running without calibration (fthd_isp.c:584-603). Consequence: worse colours/noise instead of a failure. VERIFIED (code), effect on the image NOT VERIFIED.
- `MODULE_FIRMWARE` declares `firmware.bin` and all 11 set files (fthd_drv.c:572-583; confirmed in the built module with `modinfo`). VERIFIED.

### V4L2 (fthd_v4l2.c)
- YUYV only (e5a4f89/#346; enum_fmt :458-467, try_fmt :505-506). VERIFIED.
- Sizes stepwise: width 320..sensor width in steps of 8, height 240..sensor height (:667-684); default format = native sensor size. VERIFIED.
- Frame interval only discrete 1/30 (:689-712); AE may lower the rate (85384e6). VERIFIED.
- `G_SELECTION` returns the native sensor bounds (:643-662, cf632f3). VERIFIED.
- Crop centred, then scaling (8c771b5); odd width/outside the sensor refused (7cde4b1, 3308511); `crop_set` now sets `cmd.y1` (fthd_isp.c:764). VERIFIED.
- For the 12-inch models: native geometry 848x588 (comment fthd_drv.h:110-112, #326, #327). NOT VERIFIED on the test machine.
- Important for judging the quality: output > 848x588 (e.g. 1280x720) is ISP upscaling, not native resolution. #326 measures non-uniform scaling (vertically 720/y2).

### Firmware upload
- `request_firmware("facetimehd/firmware.bin")`, copy into 8 MB of device memory (fthd_isp.c:145-174). No version check, no model-dependent selection. VERIFIED (agent, spot check).

### Power management (fthd_drv.c:528-567)
- Legacy `pci_driver.suspend/resume`. Suspend returns `-EBUSY` if the device is open, otherwise `fthd_pci_remove()`; resume = a full `fthd_pci_probe()` including a new firmware upload (PR #337, 6e56ed8). VERIFIED (read myself).
- Consequences: (a) an open camera blocks system suspend; (b) `/dev/videoN` disappears and reappears; (c) no runtime PM, no `dev_pm_ops`, no D3hot. VERIFIED (code). Effects on the test machine NOT VERIFIED.
- `.shutdown = fthd_pci_remove`. VERIFIED.
- ACPI: only `CMPE(1)` via `ACPI_HANDLE` (fthd_isp.c:84-142), an error is only a warning. VERIFIED.
- ASPM L0s/L1/CLKPM off via `pci_disable_link_state` ("hangs while streaming", fthd_drv.c:374-377). Overrides `pcie_aspm=force` for the device. VERIFIED (code).
- Issue #271: package C-state residency worse after modprobe/rmmod (2022, another model). NOT VERIFIED for MacBook9,1, but relevant for the battery.

### DMA/IOMMU
- DMA mask 64 bit, fallback 32 bit; capture buffers as SG tables in the camera's own S2 IOMMU (fthd_buffer.c). VERIFIED (agent).
- No code or README requirement for `intel_iommu=off`. VERIFIED. The claim in the thomas-shirley README: without evidence; irrelevant for the test machine, since DMA remapping is off (HARDWARE.md). Switching it off across the board: **REFUTED as a necessity for the test machine**.

### Build
- Makefile = a simple kbuild wrapper without a compiler choice; dkms.conf with an outdated `PACKAGE_VERSION=0.7.0.1` and the deprecated `MODULES_CONF` (bdc_pci blacklist). VERIFIED.
- Kernel compatibility: 45572a4 (≥7.0), 54fb8f2 (7.2). VERIFIED.

### Relevant open PRs
- **#355** (pschatzmann, 4 commits): USERPTR enabled again, buffers with a page offset, no hang on stop, rollback on an IOMMU mapping error. Needed for PipeWire. Applies to master without conflicts, builds on the test machine. VERIFIED (merge/build).
- **#356** (draft): discards 2 dark warm-up frames instead of a 200 ms sleep in STREAMON; measured only on sensor 0005/0248. NOT VERIFIED for 9774.

## 3. Issues/PRs about the 12-inch models

| Source | Content | Status |
|---|---|---|
| [#196](https://github.com/patjak/facetimehd/issues/196) (2019, closed 2026-06-26 by #327) | MacBook9,1: works only with a fixed 640x480 crop, 1675 is the matching set file; 1.43 is not enough for the 10,1 | VERIFIED (agent via gh) |
| [#327](https://github.com/patjak/facetimehd/pull/327) (merged 2026-06-26) | sensor size from the firmware, 30 fps information; tested only on MacBook8,1 | VERIFIED |
| [#326](https://github.com/patjak/facetimehd/issues/326) (open) | the 10,1 needs CMPE before init, otherwise "No wake signal"; a stuck ISP is only freed by a cold boot. 9,1 comment: no CMPE needed, 848x588 crop, aspect-correct `[0,0][848,477]`→1280x720 | VERIFIED (comments read myself) |
| #308 (open) | MacBook8,1 green image, SIF 0x804; probably fixed by #327 | NOT VERIFIED |
| #239, #271 | hibernate hang (Air7,2), C-state residency | NOT VERIFIED for the 9,1 |
| facetimehd-firmware PR #12 (merged 2026-08-19) | firmware 5.60.0 + 11 set files from macOS 10.12.6, sha256 pinned; tested on MacBook10,1 | VERIFIED (agent) |

## 4. Assessment of the named solutions

| Solution | Actual change (code) | Class |
|---|---|---|
| patjak/facetimehd master c9b063a | see section 2 | **Only tested on related hardware** (upstream itself: 8,1, 10,1, Air/Pro); the 9,1 only proven by a third party with an older state (kernel 7.1.5, before the September crop commits) |
| PR #327 | contained in master | **Demonstrably tested on MacBook9,1** only indirectly via the #326 comment; the PR itself: 8,1 |
| thomas-shirley/macbook8.1-camera | copy of the driver byte-identical to upstream 25bbe7b (= PR #327); in addition a script that sets `intel_iommu=off` in GRUB | **Outdated or unsuitable** (merged into upstream; IOMMU script unfounded) |
| id1man23/macbook12-camera-fix | replaces 3 whole files (base ≈ 45572a4): DMI test 8,1/9,1/10,1, max. 640x480, fixed crop, frametime 33 | **Outdated or unsuitable** (overwriting the files removes newer fixes, e.g. the suspend safeguard; the 640x480 hack contradicts the sensor detection). Claimed 9,1 tests without logs |
| neron82/macbook10-1-facetimehd-linux | patch: CMPE via a fixed ACPI path, fallback D0/D3hot, 640x480, hardening; firmware 1.55 | **Only tested on related hardware** (MacBook10,1, logs available). For the test machine: the ACPI handle part is unnecessary, since `firmware_node` = CMRA |
| macbook91-cs4208 (the same author's audio driver) | audio DKMS of the same model; template for the lockfile, compiler choice, release promotion, recovery tools | **Architecture template**, no camera code |
| juicecultus/facetimehd (fork) | "aspect-matched centered crop + set cmd.y1", 66 commits behind master | **Plausible but not verified**; superseded in content by master |
| AUR facetimehd-dkms 0.7.2-1 | tag 0.7.2 (54fb8f2): contains #327, but not the crop fixes, #333, #337 | **Plausible but not verified**; without clang detection |
| AUR facetimehd-firmware 1:1.43_5-2 | firmware 1.43.0 from OS X 10.11.5 | **Outdated or unsuitable** for the 12-inch models |
| AUR facetimehd-data 5.1.5769-2 | only 9112/1771/1871/1874, no 1675 | **Outdated or unsuitable** for the 9,1 |

## 5. Firmware and calibration

| Artifact | Origin | Download size | Integrity | Status |
|---|---|---|---|---|
| firmware.bin 5.60.0 | `AppleCameraInterface` in macOSUpdCombo10.12.6.dmg (Apple CDN, 1.97 GB, HTTP 200 on 2026-10-12); range download of two xz chunks, gzip at offset 81920, length 602903 | ≈ 9 MB | sha256 according to the script `240ef2e9…4330` | script VERIFIED, hashes not computed myself |
| 1675_01XX.dat | `AppleCameraAssistant` (same DMG), offset 430080, 18044 bytes | ≈ 8.8 MB | sha256 according to the script `b7a38aef2755721bb28c92d84a15654b17e9fb3b0a0f088a384a981fc8fe16d6` | as above |
| firmware.bin S2ISP-01.55.00 | Boot Camp (newer ESD) | 400-540 MB | no pinning source found | proven on the 9,1 by a third party |
| firmware.bin 1.43.0 | OSXUpd10.11.5.dmg | ≈ 3 MB range | sha256 according to the script `e3e6034a…2d3d` | unsuitable for the 12-inch models (proven for the 10,1) |

- Differing 1675 hashes in sources: #326 gives md5 `96c3f4aa…`, the wiki `83b854f9…`. Cause unknown (possibly different versions). NOT VERIFIED. After extraction only the pinned sha256 counts.
- The extractor uses `curl -k` (TLS verification off). Integrity depends solely on the pinned hashes. VERIFIED (agent). Plan: run it without `-k`.
- Differences between the initialization stages: firmware boot (upload + ISP start), sensor detection (CH_INFO_GET; with 1.43 "sensor count 0"), calibration (set file, optional), video (CROP/OUTPUT_CONFIG + CH_START). Errors of each stage can be told apart in the log (test plan T2).
- macOS Recovery/BaseSystem: tools from macbook91-cs4208 (`macbook91-fetch-macos-recovery`, `-verify-recovery-image`) exist; whether current recovery images contain `AppleCameraInterface` is NOT VERIFIED. At ≈ 18 MB the 10.12.6 range route is the smallest known one.
- Legal: Apple binary data may not be redistributed (license texts in the AUR package). Therefore: extraction locally at installation time, no binary data in the repository. Whether the range extraction touches Apple's SLA is a legal question that is not answered here.

## 6. Corrected assumptions

- "`_PTS` waits up to 5 s and powers the camera off": **REFUTED** for Linux on the test machine (OSDW true, 2.2 ms measured). My interim report in the session was wrong before this check.
- "bdc_pci must be blacklisted": **REFUTED** for the test machine (module not built).
- "intel_iommu=off needed": **REFUTED** for the test machine (DMA remapping is off anyway).
- "The camera delivers 640x480" (id1man23/neron82): superseded for the 9,1 by the sensor detection, 848x588; NOT VERIFIED on the test machine.

## Addendum phase 2 (2026-10-13)

Status of statements that were open before, after measurements on the test machine (details: `measurements/2026-10-13-phase2/`, design: `POWER-RECOVERY.md`):
- Firmware 5.60.0 from macOS 10.12.6 works on the MacBook9,1; it reports itself as **S2ISP-01.57.00**, sensor 0005/9774 with `1675_01XX.dat`. The Boot Camp firmware 01.55 is not needed. **VERIFIED**
- Native geometry 848x588 at 30 fps on the test machine. **VERIFIED**
- Upstream suspend returns `-EBUSY` with the camera open and blocks the system suspend. **VERIFIED**; fixed by patch 0008.
- Upstream counts a signal to the streaming process as a firmware timeout (`wait_event_interruptible_timeout`). **VERIFIED** (60 false timeouts measured); fixed by 0006.
- `isp_init()` has leaks and NULL dereferences in error paths and a `BUG_ON` at the second bring-up. **VERIFIED** (code); fixed by 0005.
- `vb2_wait_for_all_buffers()` in `stop_streaming` waits without limit when the firmware hangs. **VERIFIED** (code); fixed by 0009.
- macOS recovers from a stalled image processor with a full power cycle via `CMPE` (frame watchdog in the userspace part, 250 ms off, 20 ms after power-on). **VERIFIED** (analysis of the macOS binaries, only the timing taken over).
- #356 (warm-up frames) was not taken over; still NOT VERIFIED for sensor 9774.
- Issue #271 (C-state residency): not yet measured on the test machine.
