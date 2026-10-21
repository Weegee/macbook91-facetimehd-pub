# IMPLEMENTATION-PLAN: the MacBook9,1 camera as a DKMS driver

As of 2026-10-13. Status at that time: **draft, waiting for approval.** Nothing of it had been carried out except phase 1. Historical plan: the implementation ran from 2026-10-13 on (releases 20261013.01 to 20261019.01); status and open points are in `docs/test-status.json` and `docs/CHANGELOG.md`. Paths, commands and module names here are the state of the plan, not today's tree.

Principle: upstream first. Own patches only for errors measured on the test machine. Every phase ends with a decision point (G = gate). Every change to the system can be undone individually and is announced beforehand.

Rights legend: **U** = user, **R** = root (sudo/askpass), **R!** = root and a system change (approval first).

## Blockers (to be solved before a successful implementation)

| # | Blocker | Solution | Phase |
|---|---|---|---|
| B1 | No firmware/set file on the test machine | extraction F1, fallback F2 | 3 |
| B2 | Firmware 5.60.0 untested on MacBook9,1 | gate G3 with log evaluation, fallback 01.55 | 3/4 |
| B3 | PipeWire broken with master (#333) | include PR #355, measure on the test machine | 4 |
| B4 | The DKMS build needs `LLVM=1` for 7.2.9 and GCC for 6.18-LTS | compiler choice from `.config` as in cs4208 | 7 |
| B5 | Suspend with the camera open → `-EBUSY` (code) | measure (T8), possibly patch P1 | 5 |
| B6 | A stuck ISP can only be freed by a cold boot (#326, 10,1) | order the tests so that a cold boot is available; check the recovery path | 4/5 |

## Phase 1: Research and inventory — COMPLETED

Result: RESEARCH.md, HARDWARE.md, OPTIONS.md, TEST-PLAN.md, a project-state note, `docs/diag/`. Not carried out: hardware tests, downloads of proprietary data.

## Phase 2: Baseline and controlled preparations

### 2.1 Repository and working tree
- Goal/measures: `git init`, first commit of the phase 1 documents; the local evidence directory stays ignored. Upstream c9b063a and PR #355 (head commit e678cdc) as the reference in `packaging/upstream.lock` (commit IDs, tarball sha256).
- Preconditions: approval of the plan. Files: repository root, `packaging/upstream.lock`.
- Commands: `git init`, `git -C <clone> archive c9b063a | sha256sum`. Rights: U.
- Result: a clean Git state, a reproducible source base. Risks: none.
- Tests: `git status` clean, lock hash reproducible. Alternative: —. Effort: 0.5 h, priority high.

### 2.2 Measurement baseline without the camera driver
- Goal: reference values for battery and suspend before code is loaded.
- Measures: package C-state residency and power draw at idle (5 min, battery, fixed screen), S3 cycle duration from `journalctl`, camera PMCSR (`setpci -s 03:00.0 0x4c.w`), RP10 ASPM.
- Preconditions: 2.1. Files: `tools/dev-power-baseline.sh` (it replaced the planned `tests/hw/baseline.sh`), results in `docs/measurements/`.
- Commands: `turbostat --quiet --show Pkg%pc2,Pkg%pc3,Pkg%pc6,PkgWatt -i 10 -n 30` (R, read-only), `cat /sys/class/power_supply/BAT0/power_now`. A manual suspend cycle only with approval.
- Rights: R (read-only), suspend: R! (approval).
- Result: table of idle power/C-states/suspend time. Risks: low.
- Tests: T0 (TEST-PLAN). Alternative: `powertop --csv`. Effort: 1 h, priority medium.

### 2.3 Test tools
- Measures: optionally install `gst-plugins-good` (v4l2src); otherwise ffmpeg/v4l2-ctl. `v4l2-compliance` is available.
- Rights: R! (package installation, approval). Risks: no effect on the driver. Effort: 0.2 h.

**G2:** baseline available → phase 3.

## Phase 3: Obtaining and verifying the firmware

### 3.1 Extraction F1 (5.60.0 + 1675)
- Goal: `firmware.bin` and `1675_01XX.dat` local, hash-checked, outside the repository.
- Measures: `patjak/facetimehd-firmware` @ 60ee212 in a scratch directory, review the script, remove `curl -k`, range download from `updates.cdn-apple.com` only; output to `~/.local/share/macbook91-facetimehd/firmware/` (no `/usr/lib/firmware`).
- Preconditions: approval for the Apple download (≈ 18 MB). Tools: curl, xz, gzip, dd, sha256sum.
- Commands: `make` in the extractor with the target directory variable, or manually `curl -r` + `xzcat` + `dd`; then `sha256sum`.
- Rights: U.
- Result: sha256 of `firmware.bin` = `240ef2e9…4330` (5.60.0), `1675_01XX.dat` = `b7a38aef…16d6`. A mismatch = abort.
- Risks: Apple URL gone (currently HTTP 200); license (local use only).
- Tests: hash comparison, the extractor's header/footer check. Alternative: F4 (full DMG) as a cross-check, F2 (Boot Camp 01.55).
- Effort: 1 h, priority high.

### 3.2 Documenting the provenance
- Measures: `docs/FIRMWARE.md` with URL, byte ranges, hashes, date, tool versions. No binary data in the repository.
- Rights: U. Effort: 0.5 h.

### 3.3 Fallback F2 (only if G3 fails)
- Find the Boot Camp ESD with S2ISP-01.55.00 (Apple catalog), smallest package, check signature/hash, extract with 7z. Download 400-540 MB: separate approval.

**G3** (decided in phase 4): sensor 0005/9774 detected and set file 1675 loaded → F1 stays. Otherwise F2.

## Phase 4: Minimal prototype (upstream + #355, unpackaged)

### 4.1 Build
- Measures: working copy c9b063a + #355 in `build/`, `make -C /usr/lib/modules/$(uname -r)/build M=$PWD LLVM=1`. Already successful in the compile test.
- Rights: U. Effort: 0.2 h.

### 4.2 Controlled loading (first real contact with the hardware)
- Goal: decide gate G1: does upstream + #355 work on the test machine?
- Measures:
  1. Firmware search path temporarily: `echo -n ~/.local/share/macbook91-facetimehd/firmware-root > /sys/module/firmware_class/parameters/path` (the directory contains `facetimehd/`). Nothing is written to `/usr/lib/firmware`.
  2. `modprobe videobuf2-dma-sg videobuf2-v4l2 videodev`, then `insmod build/macbook91-facetimehd.ko`.
  3. Logs, `v4l2-ctl --all`, formats, 300-frame capture, `v4l2-compliance -s`.
  4. `rmmod macbook91_facetimehd`, clear the path parameter.
- Preconditions: phase 3, approval, a running session without important open work (risk B6), power adapter.
- Files: no system files. Rights: R! (loading a module).
- Result: dmesg shows the firmware version, `sensor id: 0005 9774`, set file 1675 loaded; `/dev/videoN` delivers frames.
- Risks: the ISP hangs until a cold boot; kernel warning/oops (taint); module cannot be unloaded. Countermeasure: only in a safe session, logs made persistent beforehand (`journalctl -k -f > file`).
- Tests: T1-T5. Alternative on failure: F2 firmware; analysis per stage (firmware boot / sensor / set file / stream).
- Effort: 2 h, priority highest.

### 4.3 PipeWire and browser cross-check
- Measures: check the PipeWire camera node (`wpctl status`, `pw-cli ls Node`), Firefox WebRTC test page, once without #355 (plain master) to confirm B3.
- Rights: U (module swap R!). Tests: T6. Effort: 1 h.

**G1:** all mandatory criteria T1-T6 PASS → phase 5 only for the suspend/battery points, phase 7 possible directly. Sensor not detected → G3/F2. Stream broken despite the sensor → phase 5 with an error analysis.

## Phase 5: Fixing hardware-dependent errors (proven ones only)

Every item starts only with measured evidence from phase 4/2.

| Step | Trigger | Measure | Files | Risk | Alternative |
|---|---|---|---|---|---|
| 5.1 Suspend with the camera open | T8: suspend fails with `-EBUSY` | `dev_pm_ops` with `suspend`: stop the stream, vb2 buffers `VB2_BUF_STATE_ERROR`, stop the firmware; `resume`: ISP + firmware anew, `video_device` stays registered | fthd_drv.c, fthd_v4l2.c | races stream/suspend, deadlocks | upstream behaviour + documentation that applications must close before suspend |
| 5.2 First frames dark/STREAMON slow | T4: latency > criterion | measure PR #356 on 0005/9774, possibly sensor-dependent | fthd_v4l2.c, fthd_isp.c | image errors at the start | stay at 200 ms |
| 5.3 ISP hang | T7: open/close loop hangs | CH_RESET/restart path, timeouts, clean error return | fthd_isp.c | cold boot needed | module reload |
| 5.4 Battery | T9: C-state loss > criterion | shut the ISP down after close; optionally runtime PM with `CMPE(0/1)` | fthd_drv.c, fthd_isp.c | ISP hang after restarting | load the module only when needed |
| 5.5 Geometry | T3: distortion/crop wrong | aspect check, possibly a 16:9 window `[0,0][848,477]` only for 16:9 output | fthd_isp.c | — | upstream behaviour |

Rights: U for code, R! for every test. Patches as `patches/NNNN-*.patch` with the measured evidence in the commit. Goal: send them upstream. Effort 2-8 h each, priority according to the finding.

**G5:** all proven errors fixed or documented as a known limitation.

## Phase 6: Image quality and stability

- Measures: exposure/white balance/controls (`v4l2-ctl -L`) against a reference scene; noise (standard deviation on a grey area) and sharpness (edge measurement) at 848x588 native; comparison with/without the set file; frame rate under artificial light/darkness (AE lowers the rate).
- Result: measured values in `docs/measurements/quality-*.md`; no upscaling presented as "native resolution".
- Rights: U (module R!). Tests: T3, T10. Effort: 4 h, priority medium.

## Phase 7: DKMS integration and CachyOS packaging

- Goal: package `macbook91-facetimehd-dkms` (driver) and separately `macbook91-facetimehd-firmware-local` (only the extraction script + hash list, downloads at installation, no Apple data in the package) or a purely manual extraction script.
- Measures:
  - `packaging/fetch-upstream.sh` builds `src/macbook91-facetimehd/` from the lockfile + `patches/`; a hash error = abort.
  - `dkms.conf`: `PACKAGE_NAME=macbook91-facetimehd`, `BUILT_MODULE_NAME[0]=macbook91-facetimehd` (module name `macbook91_facetimehd`, conflict with `facetimehd-dkms` via the PKGBUILD), `DEST_MODULE_LOCATION[0]=/updates`, `AUTOINSTALL=yes`, no `MODULES_CONF`.
  - Makefile with a `check` target: compiler family from `$(KDIR)/.config` (`CONFIG_CC_IS_CLANG=y` → `LLVM=1`), check of `Module.symvers`, `utsrelease.h`.
  - Hardware gating: the module binds only 14e4:1570 (PCI ID table); in addition no autoload rule outside the modalias.
  - No blacklist entry (bdc_pci does not exist).
  - `MODULE_VERSION` with pkgver + source hash as in cs4208, verification script `macbook91-facetimehd-verify`.
  - Signing via the DKMS MOK (present); Secure Boot is off.
- Files: `packaging/arch/PKGBUILD`, `.install`, `src/macbook91-facetimehd/dkms.conf`, `Makefile`.
- Commands: `makepkg` in a clean chroot or `build/arch`, `namcap`, `dkms build -k 7.2.9-1-cachyos`, `-k 6.18.55-1-cachyos-lts`.
- Rights: U for the build, R! for the installation.
- Result: the package builds reproducibly (same sha256 for two builds), DKMS builds for both kernels.
- Risks: conflict with AUR packages (`conflicts=('facetimehd-dkms' 'facetimehd-dkms-git')`). No contact with macbook91-cs4208.
- Tests: T11, T12. Alternative: upstream dkms.conf + wrapper. Effort: 6 h, priority high.

## Phase 8: Automated tests, regression, security review

- Hermetic tests (U): lockfile/patch integrity, build against both kernels' headers, `sparse`/`smatch` (from source, in a temporary directory), `scripts/checkpatch.pl` on own patches, clang `-Wall -Wextra` + `scan-build`, `coccicheck` for own files.
- Dynamic (R!): test kernel with KASAN, lockdep (`PROVE_LOCKING`), kmemleak, `DEBUG_ATOMIC_SLEEP` (the CachyOS kernel lacks these; an own debug kernel as an additional boot entry, not the default); `v4l2-compliance -s`, loop tests T7/T8; optionally `intel_iommu=on` as a robustness test.
- Adversarial audit (see the audit section of TEST-PLAN): DMA/memory safety, races, error paths, firmware/set-file validation (size, header), kernel API, suspend races, supply chain (lockfile, hashes, no `curl -k`), effects on other devices.
- Result: `docs/test-status.json` machine-readable, every test with PASS/FAIL/NOT RUN.
- Effort: 8-12 h, priority high before publication.

## Phase 9: Release, installation, rollback

- Measures: `release/<pkgver>/` with PKGBUILD, source tarball, status note; GitHub release with `.pkg.tar.zst`; installation and rollback instructions.
- Rollback: `sudo pacman -R macbook91-facetimehd-dkms` → DKMS removes the module, `depmod`; firmware: `rm -r /usr/lib/firmware/facetimehd` (if installed) or delete the local directory; proof: `modinfo facetimehd` fails, `lspci -k` without a driver.
- Tests: T13 (installation, reboot, uninstallation, reboot, initial state identical to HARDWARE.md).
- Rights: R!. Effort: 3 h.

## Decision overview

```
Phase 2 → Phase 3 (F1) → Phase 4: G1/G3
  G1 PASS ─────────────────────────────→ Phase 7 → 8 → 9 (phase 5/6 only for suspend/battery/quality)
  Sensor 0 / firmware error → F2 (3.3) → phase 4 again
  Stream/PipeWire error     → Phase 5 → Phase 6 → 7
```

## Total effort (estimate, NOT VERIFIED)

Best case (G1 PASS): 15-20 h. With the suspend rework and battery work: 35-50 h.
