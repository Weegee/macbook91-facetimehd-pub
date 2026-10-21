# HARDWARE: diagnosis of the test machine (MacBook9,1)

As of 2026-10-13, boot 0 since 2026-10-12 22:47. All commands read-only. Root commands via `tools/dev-root-diag.sh` (dmidecode, lspci -vvv/-xxxx, copy of `/sys/firmware/acpi/tables`). Raw data: kept outside the repository (not published). Sanitized excerpts: `docs/diag/`.

## Model and firmware

| Property | Value | Status |
|---|---|---|
| Model | MacBook9,1 (DMI `product_name`) | VERIFIED (`diag/dmi-excerpt.txt`) |
| Board ID | Mac-9AE82516C7C6B903 | VERIFIED |
| Boot ROM | 522.0.0.0.0 of 08/17/2023 | VERIFIED |
| CPU, RAM | Core m3-6Y30, 4 threads, 8 GB | VERIFIED |
| Secure Boot | not supported/off; lockdown `none` | VERIFIED (`bootctl`, `/sys/kernel/security/lockdown`) |

## Camera (PCIe)

| Property | Value | Status |
|---|---|---|
| Device | `0000:03:00.0` Broadcom 720p FaceTime HD `[14e4:1570]`, subsystem 14e4:1570, class 0x0480 | VERIFIED |
| Upstream port | `0000:00:1d.1` (RP10, Intel 9d19), link 5 GT/s x1 | VERIFIED (`diag/lspci-rp10-vvv.txt`) |
| BARs | BAR0 64 K, BAR2 256 M prefetch, BAR4 1 M | VERIFIED |
| Driver bound | none; no modalias match in `modules.alias` | VERIFIED (`modprobe -R` fails) |
| Power | `power_state=D0`, runtime `suspended`, `d3cold_allowed=1`, PM capability: D1, D3hot, no D3cold PME | VERIFIED |
| MSI | present, currently off (no driver) | VERIFIED |
| ASPM | device and RP10 each `ASPM L1 Enabled` (result of `pcie_aspm=force`; the FADT reports "no ASPM") | VERIFIED (`diag/kernel-log-excerpt.txt`) |
| AER/DevSta | `CorrErr+ UnsupReq+` set (cause unknown, possibly enumeration) | value VERIFIED, cause NOT VERIFIED |
| ACPI node | `firmware_node/path` = `\_SB_.PCI0.RP10.CMRA` | VERIFIED |

Consequence: `ACPI_HANDLE(&pdev->dev)` in the upstream driver (fthd_isp.c:95) finds the `CMRA` node on the test machine. The direct ACPI path from neron82 is unnecessary here. This is an inference from the sysfs value, NOT VERIFIED in a driver run.

## ACPI: camera power sequencing (DSDT)

Source: the test machine's DSDT, decompiled with iasl 20251212 (from a signed Arch package, unpacked only in a temporary directory). The decompiled excerpts are Apple's ACPI code and are not part of this repository; this section describes, in this project's own words, what the methods do.

- `\_SB.PCI0.RP10.CMRA.CMPE(Arg0)`:
  - `CMPE(1)`: GPIO 0x02000010 as input (`SGDI`), wait 100 ms, RP10 ASPM to the saved value `S2PM` (initially 2 = L1), root port to D0, wait up to 1 s for link active (`LACT`, polled every 10 ms), L2/3 ready exit, `LEDM=0`.
  - `CMPE(0)`: camera PMCSR to D3hot (`DPST=3`), L2/3 ready entry, RP10 to D3, save ASPM and switch it off, GPIO 0x02000010 as output low. This powers the camera off.
- `_PTS(3)` calls `CMPE(0)` (waiting for D3hot with up to 5000 x `Sleep(1)`) **only if `!OSDW()`**. `_WAK(3)` likewise calls `CMPE(1)` only without Darwin. VERIFIED (DSDT).
- `OSDW()` is true when `OSYS == 0x2710`, which is set on `_OSI("Darwin")`. On Apple hardware Linux reports `_OSI("Darwin")`: log "DMI detected to setup _OSI("Darwin")", "BIOS _OSI(Darwin) query honored via DMI". VERIFIED.
- So on the test machine the firmware does **not** power the camera off via `_PTS` on S3 and does not wait for D3hot. Measurement in the previous boot: "Preparing to enter system sleep state S3" to "Saving platform NVS memory" = 2.2 ms. VERIFIED (journalctl boot -1).
- Under Darwin semantics `CMPE` is the job of the operating system's driver. Upstream only calls `CMPE(1)` (fthd_isp.c:84-142), never `CMPE(0)`. Whether a runtime power-off via `CMPE(0)` saves battery is NOT VERIFIED.
- `CMPE(1)` writes the ASPM bits of RP10 directly, bypassing the kernel. Possible interaction with `pci_disable_link_state()` in the driver: NOT VERIFIED.
- Wakeup: RP10 S3 `enabled` in `/proc/acpi/wakeup` (`diag/acpi-wakeup.txt`).

## Kernel and toolchain

| Property | Value | Status |
|---|---|---|
| Running kernel | 7.2.9-1-cachyos, PREEMPT_DYNAMIC, HZ=1000 | VERIFIED |
| Compiler | clang 23.1.1 + LLD, ThinLTO (`CONFIG_LTO_CLANG_THIN=y`) | VERIFIED (`/proc/version`, Kconfig) |
| Second kernel | 6.18.55-1-cachyos-lts, **GCC 16.2.1** | VERIFIED |
| Headers | both installed | VERIFIED (pacman) |
| Toolchain | clang/llvm/lld 23.1.1, gcc 16.2.1, dkms 3.4.3 | VERIFIED |
| Module signing | `MODULE_SIG=y`, not enforced; DKMS MOK under `/var/lib/dkms/mok.*` | VERIFIED |
| V4L2/vb2 | `VIDEO_DEV=m`, `VIDEOBUF2_DMA_SG=m`, `VIDEOBUF2_V4L2=m` | VERIFIED |
| Debug | `DYNAMIC_DEBUG`, `FTRACE`, `DEBUG_INFO_BTF`, `PM_DEBUG`; no KASAN, no lockdep, no kmemleak | VERIFIED (`diag/kconfig-excerpt-7.2.9-1-cachyos.txt`) |

Compile test (build in a temporary directory only, nothing installed/loaded):

| Source | Kernel | Result |
|---|---|---|
| upstream c9b063a | 7.2.9 with `LLVM=1` | rc=0, 0 warnings, `facetimehd.ko` |
| upstream c9b063a | 6.18.55-lts (GCC) | rc=0, 0 warnings |
| c9b063a + PR #355 | 7.2.9 with `LLVM=1` | merge without conflicts, rc=0, 0 warnings, vermagic `7.2.9-1-cachyos` |

## IOMMU and DMA

- `CONFIG_INTEL_IOMMU=y`, `# CONFIG_INTEL_IOMMU_DEFAULT_ON is not set`, no `intel_iommu=` on the command line. VERIFIED.
- `/sys/kernel/iommu_groups` empty, camera without `iommu_group`: DMA remapping is off; only interrupt remapping (x2apic) is active. VERIFIED.
- Consequence: `intel_iommu=off` is not needed on the test machine, because DMA translation is already off. VERIFIED for the current configuration.
- DMAR RMRR 0x8b800000-0x8fffffff (probably iGPU stolen memory). Relation to the camera NOT VERIFIED.

## Suspend

- `mem_sleep`: `s2idle [deep]` (S3 active). VERIFIED.
- Previous suspends without a camera driver were unremarkable (boot -1). Not tested with the driver.

## Existing software

| Component | State | Status |
|---|---|---|
| Camera driver/firmware | none; `/usr/lib/firmware/facetimehd` missing; no `/dev/video*` | VERIFIED |
| DKMS | only `macbook91-cs4208/20261006.01` (audio, do not touch) | VERIFIED |
| Conflict bdc_pci | `CONFIG_USB_BDC_PCI` not set in either kernel; only `bdc.ko` (platform), no alias for 14e4:1570 | VERIFIED |
| modprobe.d | no entries for the camera/V4L | VERIFIED |
| Multimedia | PipeWire 1.6.9, WirePlumber 0.5.18, xdg-desktop-portal 1.22.1 + KDE 6.7.5, GStreamer 1.28.7, v4l-utils 1.32.0, ffmpeg, qv4l2, Firefox 157 | VERIFIED |
| Missing for tests | `libcamera` (not needed), `gst-plugins-good` (v4l2src), `v4l2-compliance` is in v4l-utils | VERIFIED |
| Firefox pref `media.webrtc.camera.allow-pipewire` | not set (default value) | VERIFIED; default value in FF 157 NOT VERIFIED |

## Side findings (not relevant to the camera)

- ACPI error `AE_ALREADY_EXISTS` in CPU SSDTs and `\_SB.OSCP` not resolvable: a known quirk of Apple firmware. Relation to the camera: none apparent.
- Bluetooth `BCM: failed to write update baudrate (-16)`.

## Not determined

- Sensor ID, firmware version and formats: only possible with the driver and firmware loaded (phase 2).
- `acpidump` is missing; replaced by a copy of `/sys/firmware/acpi/tables` (equivalent for DSDT/SSDT).

## Addendum phase 2 (2026-10-13)

- `CMPE(1)` writes back the RP10 ASPM field saved at `CMPE(0)`. Since the driver switches ASPM off at probe, it stays off after every power cycle (camera LNKCTL 0x0040, RP10 0x0c42). The suspected interaction with `pci_disable_link_state()` is therefore **REFUTED** for this sequence.
- `CMRA` has no `_PS0`/`_PS3`/`_PR3`; power only via `CMPE`. **VERIFIED (DSDT)**
- After a cold start of the chip `PME_En` is set (PMCSR 0x4108). **VERIFIED**; the driver clears it.
- After S3 the camera is reachable before the driver runs (no "device inaccessible" in several S3 cycles). **VERIFIED**
- Power cycle via `CMPE(0)`/`CMPE(1)` including DDR training and firmware boot: 0.96–0.98 s. **VERIFIED**
- The Wi-Fi chip (BCM4350, 02:00.0) sits on the neighbouring root port RP09 (00:1d.0). In ACPI there is no resource shared with `CMPE`. A Wi-Fi firmware hang after a series of suspends is documented separately (not part of this repository); a connection with the camera is NOT VERIFIED.
- On the test machine the monotonic kernel clock stops in S3 and s2idle, and the printk timestamps directly after S3 are not reliable because of a TSC-ADJUST reset. **VERIFIED**
