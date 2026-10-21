# POWER-RECOVERY: power, suspend and hang recovery (patches 0007-0009)

As of 2026-10-13, kernel 7.2.9-2-cachyos. Measured values: `docs/measurements/2026-10-13-phase2/`.

## Hardware basics (the test machine, MacBook9,1)

- Camera `14e4:1570` on root port 00:1d.1 (`\_SB_.PCI0.RP10`), ACPI node `CMRA`. **VERIFIED (DSDT)**
- `CMRA` has no `_PS0`/`_PS3`/`_PR3`. The PCI core cannot power the camera off; only the ACPI method `CMPE(Arg)` can. **VERIFIED (DSDT)**
  - `CMPE(1)`: GPIO 0x02000010 on, wait 100 ms, write back the RP10 ASPM value saved at power-off, RP10 to D0, wait up to 1 s for the link, L2/L3 handshake.
  - `CMPE(0)`: camera D3hot, L2/L3 entry, RP10 to D3, save ASPM and switch it off, GPIO off.
- Linux reports `_OSI("Darwin")`; with that, `_PTS`/`_WAK` leave `CMPE` to the driver. Upstream only calls `CMPE(1)`, never `CMPE(0)`.
- `CMPE(1)` restores the RP10 ASPM state from before `CMPE(0)`. Because the driver already switches ASPM off at probe, it stays off after a power cycle (camera LNKCTL 0x0040, RP10 0x0c42 before and after). **VERIFIED**
- After a cold start of the chip `PME_En` is set (PMCSR 0x4108); the driver clears it as the PCI core does at boot (`pci_pme_active(false)`), 0x4008 afterwards. **VERIFIED**

## Behaviour of the macOS driver (timing facts)

From the analysis of AppleCameraInterface/AppleCameraAssistant (macOS 10.12.6), taken over as facts only, no code:
- Power on: `CMPE(1)`, then 20 ms. Power off: PCI bus master off, `CMPE(0)`, then 250 ms.
- An image processor without frames is detected by a frame watchdog in the userspace part and restarted with a full power cycle. A softer reset does not exist there.
- Command timeout 2000 ms.

## Driver design

### States
`hw_state` = `DOWN`, `STARTING`, `UP`, `FAILED` (FAILED = the chip runs but does not answer; no orderly firmware stop any more). Changes only under `vb2_queue_lock`, except the atomic transition `UP → FAILED` on hang detection.

### Bring-up, teardown, power cycle (0007)
- Probe separates the one-time setup (PCI, V4L2, debugfs) from the bring-up of the chip (buffer IOMMU, DDR, firmware). Teardown does the reverse; buffer descriptors and IOMMU entries live in S2 memory and are freed in the process, the vb2 buffers stay with the driver.
- Power cycle: bus master off, `CMPE(0)`, off for at least 250 ms (measured with boottime, which keeps running during sleep), `CMPE(1)`, 20 ms, restore the config space from the copy saved at probe (`pci_store_saved_state`), check the ID, clear `PME_En`.
- `fthd_hw_restart()`: teardown, optionally a power cycle, bring-up, map the buffers again, restart a running stream (buffers the firmware held are sent again). The recovery worker tries this up to three times; after that the buffers go back with an error and `vb2_queue_error`.
- Buffer tags returned by the firmware are checked against the driver's own buffer table before they are used.

### System suspend (0008)
- `dev_pm_ops` instead of legacy hooks. An open camera no longer blocks suspend (formerly `-EBUSY`).
- `suspend`: stop the firmware in order, teardown, the buffers stay with the driver.
- s2idle: in `suspend_noirq` save the config space and `CMPE(0)`; the PCI core leaves a device in D0 with a saved state untouched during s2idle. `resume_noirq` powers on again before `pci_pm_resume()` restores the config space (order checked in the PCI core of v7.2.9). Power-off happens only in `suspend_noirq`, so that a suspend aborted by another device never leaves a powered-off chip behind.
- S3: the PCI core's standard path, the platform powers off.
- `resume`: hands the restart to the worker (with a power cycle after S3), so that DDR training and firmware boot (≈ 0.9 s) do not delay the system resume; a stream keeps running afterwards.

### Hang detection (0009)
- Command timeout (2 s) → `FAILED`, schedule recovery. The request memory of a timed-out command can no longer be trusted afterwards; the chip is therefore always restarted.
- Frame watchdog 2 s, restarted with every buffer sent and every buffer returned; it only fires while the firmware holds buffers. An application that keeps its buffers does not trigger it.
- `stop_streaming` waits at most 2 s for the buffers. If the firmware does not answer, the chip is torn down and powered off **before** the buffers go back, so that no DMA writes into memory the application reuses.
- Hung interrupt → recovery instead of a permanently disabled interrupt.
- If the firmware hangs while idle, the next `STREAMON` restarts the chip once instead of failing.

### Idle power-off (0010)
- Background: the driver switches ASPM off on the camera link (upstream: otherwise hangs while streaming). As long as the chip has power, the CPU package therefore does not get below PC3 (measured: ≈ 0.45 W more package power than with L1). **VERIFIED**
- If no stream runs for `idle_poweroff_ms` (module parameter, default 5000, `-1` = never), teardown and `CMPE(0)` follow; the link is then off, RP10 in D3hot. The next `STREAMON` powers on again through the existing restart path (first frame after ≈ 1.13 s instead of ≈ 0.44 s).
- Recovery without a stream no longer restarts the firmware but only powers off.
- System sleep and `remove` first power a powered-off chip on again and restore the config space: otherwise the PCI core saves the config space of a dead device (all `0xff`), and a later probe needs a powered chip with its BARs set.
- Controls are set again at every stream start anyway; values set while the chip is powered off are not lost.

### Workqueues (0014)
- Idle power-off, frame watchdog and recovery run on `system_dfl_wq` (unbound; before 6.17 `system_unbound_wq`). Kernel 7.2 reports `system_wq` as deprecated. **VERIFIED** (build, symbol table); for the test machine see `docs/test-status.json` `hw.patch_0014`.
- The interrupt follow-up work (`irq_work`) stays on `schedule_work()`, that is `system_percpu_wq` on the CPU of the interrupt; not deprecated. **VERIFIED** (headers 6.18/7.2).

### Format and buffers (0015)
- `VIDIOC_S_FMT` returns `EBUSY` while the queue has buffers (like uvcvideo) and runs under `vb2_queue_lock`. Before, any open file could change the format in the middle of a stream; the next stream start or restart (recovery, resume) would have let the firmware write larger frames into the old buffers. `buf_prepare` refuses buffers that are smaller than a frame. **VERIFIED** (build 6.18/7.2); for the test machine see `docs/test-status.json` `hw.patch_0015_0016`.

### Watchdog and teardown (0016)
- The teardown stops the frame watchdog only once the interrupt follow-up work has stopped (that work restarts it for every returned buffer), and `remove` cancels it before freeing. **VERIFIED** (code, build); the race itself was not reproduced.

### debugfs (`/sys/kernel/debug/macbook91_facetimehd/0000:03:00.0/`, before 0011 `facetimehd/`)
- `state`: hw_state, streaming, suspended, recoveries, power_cycles, last_off_ms, powered_off, hangs.
- `recover` (write): forced power cycle, waits for the result.
- `inject_hang` (write): halts the ISP CPU (test).
- `debug` (write, upstream): debug command to the firmware; only while the firmware runs, otherwise `EIO` (since 0016; before, a kernel oops with a powered-off chip).
- `channel_*` (read, upstream): ring buffers of the firmware channels; with a powered-off chip "firmware not running".

## Limits and open points

- No runtime PM of the PCI core, but the driver's own idle power-off (0010). Battery effect NOT VERIFIED (only the RAPL package power was measured, on mains power; the chip's own consumption comes on top).
- If the device is unbound via sysfs while an application holds it open, `remove` frees the driver state although the file is still open (inferred from the code, NOT tested). This comes from upstream and is not fixed.
- Hibernation (freeze/thaw/restore) is implemented but NOT tested on the test machine for lack of swap.
- DMABUF streaming NOT tested (v4l2-compliance needs an exporting device).
- Kernel 6.18-LTS (6.18.55-2-cachyos-lts): booted on the test machine on 2026-10-20 with the installed 20261020.01; `macbook91-facetimehd-verify` PASS, 0 warnings (capture, idle power-off 5000 ms). **VERIFIED** (`hw.lts_kernel`). Suspend and resume on 6.18, with and without the camera open, NOT tested (`hw.lts_suspend`); the verify tool's deprecated-workqueue check cannot fire on 6.18; only 7.2 reports that warning.
- A real (not injected) firmware hang has not been observed on the test machine so far; the tests halt the ISP CPU instead.
