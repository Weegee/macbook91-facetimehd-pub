# Measurements phase 2, 2026-10-13 (test machine, MacBook9,1)

Firmware 5.60.0 (reports S2ISP-01.57.00), set file 1675_01XX.dat, sensor 848x588 YUYV. Power adapter connected. Module loaded via `insmod` with `firmware_class.path` pointing to a local firmware directory. The raw data (t4–t12) is kept locally and is not part of this repository.

Kernel: until about 10:47 7.2.9-1-cachyos, after that 7.2.9-2-cachyos (unattended update at a reboot). 6.18.55-LTS: only the build checked.

## Upstream c9b063a + PR #355 (base, before own patches)

| Test | Result | Status |
|---|---|---|
| Firmware boot, set file | S2ISP-01.57.00, 1675 loaded | VERIFIED |
| Format | 848x588 native, stepwise 320x240–848x588, 30 fps | VERIFIED |
| Stream 300 frames | 30.02 fps, interval 31.6–35.1 ms, no gaps, 300 different frames, plausible U/V | VERIFIED |
| Image orientation | confirmed as correct by the user | VERIFIED |
| PipeWire (1.6.9) | works with #355 | VERIFIED |
| 100× open/close | 1.37–1.40 s each, no slab growth | VERIFIED |
| 20× rmmod/insmod | load time 0.58–0.97 s | VERIFIED |
| Suspend closed | S3 2×, s2idle 1× ok | VERIFIED |
| Suspend open | S3 aborted with `-EBUSY` | VERIFIED (upstream defect) |
| Error pattern | a signal to the streaming process causes false `IO/BUF_H2T: timeout` (60×) | VERIFIED, fixed in 0006 |

## 0007 Power-cycle recovery (debugfs `recover`)

| Test | Result |
|---|---|
| Power cycle closed, 21× | all ok, 963–976 ms until the firmware is ready |
| Power cycle with a running stream, 11× | all ok, stream complete (300/600 frames), one gap 1.26–1.31 s, sequence without gaps |
| Image content after recovery | Y/U/V and variance as before; first frames ≈ 6 steps darker, settled after ≈ 5 frames (auto exposure) |
| Memory | SUnreclaim before/after 30 cycles equal (156 872 kB) |
| PCI after a cycle | camera LNKCTL 0x0040, RP10 0x0c42 unchanged; PMCSR 0x4008 (after the PME fix) |
| Kernel log | no warning, no error |

Observation: a single frame interval of 44 ms without a sequence gap under test load (timestamp jitter of the workqueue-based IRQ path).

## 0008 System suspend

Real sleep cycles, each followed by a post-stream (30 frames):

| Path | Camera | Cycles | Result |
|---|---|---|---|
| rtcwake S3 | closed | 5 | ok |
| rtcwake S3 | stream running (900 frames) | 5 | ok, stream complete, one gap each of 1.79–1.83 s |
| rtcwake s2idle | closed | 4 | ok, camera powered off during sleep (`last_off_ms` ≈ sleep duration) |
| rtcwake s2idle | stream running | 4 | ok, one gap each of 2.73–2.83 s |
| `systemctl suspend` (S3, systemd-sleep, TLP/LID hooks) | closed 2, open 2 | 4 | ok, gap 1.93–1.94 s |

In total 22 real suspends (18 with 0008, 4 with 0009) without errors; camera `up` again 29–264 ms after returning from rtcwake; resume asynchronous (`PM: suspend exit` before the end of the firmware boot). No `inaccessible` message from the PCI core. Slab balance neutral for each series.

Not counted as suspends: 6 attempts in the morning that the Wi-Fi driver brcmfmac aborted after a firmware hang of the Wi-Fi chip; the camera survived this abort path every time. Wi-Fi finding: see the macbook91-wireless project (not part of this repository).

Note: printk timestamps directly after S3 are unreliable on the test machine (TSC-ADJUST reset); duration and sequence were proven via driver counters.

## 0009 Hang detection (debugfs `inject_hang` halts the ISP CPU)

| Test | Result |
|---|---|
| H1 hang with a running stream | watchdog after 2.06 s, power cycle and restart 1.16 s, stream complete |
| H2 hang while idle, then STREAMON | command timeout 2 s, restart in `start_streaming`, stream ok; no double power cycle |
| H3 stream end during a hang | close after 2.09 s (before: unbounded), chip powered off before the buffers are returned, next stream ok |
| H4 10× H1 | 10/10 ok, gap 3.23–3.28 s, only the first attempt needed, slab neutral |
| Suspend regression with 0009 | 4/4 ok, no false watchdog alarm |

## T10 endurance run (0009, kernel 7.2.9-2)

60 min uninterrupted stream (11:24–12:24), `v4l2-ctl --stream-mmap`, 108 000 frames requested.

| Value | Result |
|---|---|
| Frames | 108 000, sequence 0–107 999 without gaps, return value 0 |
| Frame rate | 30.02 fps (3597 s according to the timestamps) |
| Frame interval | 29.0–37.0 ms, none above 40 ms |
| Watchdog/recovery | not triggered (counters unchanged) |
| SUnreclaim (samples every minute) | 141 628–151 456 kB, at the end 10 MB below the start, no growth |
| Kernel log | no errors, warnings or timeouts from facetimehd |

VERIFIED.

## T9 substitute: package power with the module loaded vs. unloaded (power adapter)

T9 (battery discharge power) was not possible, the power adapter was connected. Substitute: turbostat (RAPL package), phases A B B A A B, each 20 s settling and 120 s measurement (12 × 10 s). A = 0009 loaded, camera closed, firmware running; B = module unloaded (the chip stays powered, `remove` does not call `CMPE(0)`).

| Mode | PkgWatt (mean, sd) | Busy% | Pkg%pc3 | Pkg%pc6 | Camera IRQs |
|---|---|---|---|---|---|
| A loaded | 0.999 W (0.024) | 2.19 | 41.7–47.3 | 0.00 | 0 |
| B unloaded | 0.996 W (0.016) | 2.13 | 42.3–43.4 | 0.00 | – |

Result: no measurable difference on the CPU side (3 mW, within the spread); the loaded driver generates no interrupts while idle. VERIFIED for the CPU side.

Limit: RAPL does not cover the camera chip (ISP, DDR). Its consumption, and with it the benefit of runtime PM (`CMPE(0)` with the camera closed), is NOT VERIFIED and needs a battery measurement without the power adapter.

### Cause: ASPM L1 of the camera link blocks package C-states

At probe the driver switches ASPM off on the camera link (upstream: "ASPM must be disabled on the device or it hangs while streaming"); this holds until a reboot, even after `rmmod` (LnkCtl 0x0040). In T0 (driver never loaded) L1 was active (0x0042) and PC6 reachable. Test: module unloaded, only the L1 bit in the camera's LnkCtl toggled via `setpci`, phases L1 OFF OFF L1, each 15 s + 120 s; afterwards 0x0040 restored, module loaded (`up`).

| Camera LnkCtl | PkgWatt (sd) | Pkg%pc3 | Pkg%pc6 | Pkg%pc7 | Busy% |
|---|---|---|---|---|---|
| 0x0042 (L1 on) | 0.540 (0.031) / 0.529 (0.014) | 3.3 / 4.3 | 35.3 / 34.1 | 4.1 / 3.8 | 2.23 / 2.13 |
| 0x0040 (L1 off) | 0.986 (0.008) / 0.988 (0.007) | 44.7 / 43.9 | 0 / 0 | 0 / 0 | 2.08 / 2.10 |

VERIFIED (power adapter, same load): with L1 switched off the package does not get below PC3; this costs ≈ 0.45 W of package power as long as the module was loaded once since the boot. Battery effect NOT VERIFIED (T0 on battery: 4.43 W system power, order of magnitude ≈ 10 %).

## 0010 idle power-off and 0011 module name (kernel 7.2.9-2)

0010 powers the chip off via `CMPE(0)` after `idle_poweroff_ms` (5000) without a stream. From 0011 on the module is called `macbook91-facetimehd` (lsmod `macbook91_facetimehd`); tests from the suspend series on ran with the package build (srcversion 013C85653088609DEC386E7).

| Test | Result | Status |
|---|---|---|
| Power-off | after 5 s `powered_off: 1`, RP10 PMCSR 0x0003 (D3hot), config space of the camera `0xffffffff`, no AER/error message | VERIFIED |
| Package power (phases OFF ON ON OFF, each 25 s + 120 s; ON = `idle_poweroff_ms=-1`) | median OFF 0.455 / 0.37 W, ON 0.82 / 0.83 W; Pkg%pc6 OFF 13–17 %, ON 0 | VERIFIED (power adapter; phase 1 with a higher base load, busy 5.3 %) |
| First frame | from powered off 1.12–1.14 s, within the idle window 0.44–0.45 s (5× each) | VERIFIED |
| Start/stop on both sides of the 5 s limit | 20/20 ok, 11 power-offs | VERIFIED |
| `rmmod` with a powered-off chip, `insmod` again | 2/2 ok (chip powered on again first, ID and RP10 D0) | VERIFIED |
| Hang within the idle window | chip powered off nevertheless, no unnecessary recovery, next stream ok | VERIFIED |
| Suspend | S3 and s2idle 2× each with a powered-off chip, 1× each with a stream, 3× S3 with a stream additionally: 9/9 ok | VERIFIED |
| Gap S3 with stream | 1.97–2.02 s (3×), once 2.81 s; cross-check 0009 at the same time 1.91–2.05 s (3×): no effect of 0010, outlier unexplained | VERIFIED / outlier NOT EXPLAINED |
| H1 hang in the stream | 3/3 ok, gap 3.24–3.28 s | VERIFIED |
| v4l2-compliance | 57/57, 0 warnings | VERIFIED |
| Memory | 30 cold cycles (30 power cycles): SUnreclaim 120 824 → 118 772 kB | VERIFIED |
| Kernel log | only the expected messages of the injected hangs | VERIFIED |

Note: the first suspend run with 0010 (13:09, old module) stopped after cycle 1 because the abort criterion caught a single Wi-Fi firmware timeout; the camera was ok in that cycle, and the Wi-Fi recovered by itself. The finding belongs to the separate Wi-Fi project.

## v4l2-compliance 1.32.0 (`-s`)

57/57 passed, 0 warnings: MMAP (REQBUFS and CREATE_BUFS, each without poll/select/epoll), USERPTR (without poll/select), read/write. DMABUF NOT tested (needs `--expbuf-device`).

## Package reproducibility

`packaging/fetch-upstream.sh` (c9b063a + patches 0001-0009, hashes in the lockfile) produces sources byte-identical to the tested tree; the built module has the same `srcversion` as the tested one (37922CB10A4DE6D5AA556A3). Build without a warning for 7.2.9-2 (clang/LLVM) and 6.18.55-2-LTS (GCC).

## Open

- T9 battery: the camera chip's consumption can only be determined by a battery measurement without the power adapter (user).
- DKMS installation (needs root outside the temporary rule), Firefox test (needs the user), hibernation, 6.18-LTS on hardware, DMABUF.
