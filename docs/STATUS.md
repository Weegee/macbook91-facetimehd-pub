# What has run on hardware

Measured on one MacBook9,1 (CachyOS). The record per test is `docs/test-status.json`; raw data is
in `docs/entwicklung/measurements/`. Anything not listed under "Run" has not been run.

## Run

- 100 open/close cycles, 60 minutes of streaming (108 000 frames, no gap), more than 30 real
  suspends in S3 and s2idle with and without a stream, injected hangs while streaming and idle,
  more than 60 power cycles without a memory leak, v4l2-compliance 57/57.
- Package 20261013.01 passed its hardware gate: DKMS built for both installed kernels,
  `macbook91-facetimehd-verify` PASS after a reboot.
- Patch 0017 (fixed frame sizes), with a test module: six sizes listed, every size streams,
  300 frames at 640x480 in 11.1 s, v4l2-compliance 48/48, Chromium 154 lists and opens the camera.
- Kernel 6.18 LTS: booted on 2026-10-20 with 20261020.01; the module loaded and
  `macbook91-facetimehd-verify` passed with 0 warnings (60 frames in 3008 ms, power-off after 5000 ms
  idle).
- Kernel 7.3: booted on 2026-10-24 with 20261021.01; module and firmware loaded, no driver errors
  in the kernel log.
- 20261014.01 booted: module loads, streams, powers off when idle, no deprecated-workqueue warning.

## Not run

- Hang recovery, `rmmod`, suspend and the error paths of patches 0013 to 0016 with those patches
  (`hw.patch_0013`, `hw.patch_0014`, `hw.patch_0015_0016`: NOT_RUN).
- Capture and suspend on 7.3, so 7.3 is not in `TESTED-SERIES`.
- Suspend on 6.18 (no suspend happened in that boot).
- Battery effect of the idle power-off (only CPU package power on mains was measured),
  hibernation, DMABUF streaming, a real (not injected) firmware hang.

Releases 20261013.02, 20261014.01 and 20261015.01 were released without the hardware gate.
