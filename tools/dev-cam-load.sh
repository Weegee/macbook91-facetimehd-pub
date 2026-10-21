#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-or-later
# Load a macbook91-facetimehd.ko for testing without touching /usr/lib/firmware.
# usage: dev-cam-load.sh KO FIRMWARE_ROOT   (FIRMWARE_ROOT contains facetimehd/)
set -u
KO=$1 FWROOT=$2
echo -n "$FWROOT" > /sys/module/firmware_class/parameters/path
modprobe -a videodev videobuf2-common videobuf2-v4l2 videobuf2-dma-sg || exit 1
insmod "$KO"; rc=$?
for _ in $(seq 50); do ls /dev/video* >/dev/null 2>&1 && break; sleep 0.1; done
echo "insmod rc=$rc"
