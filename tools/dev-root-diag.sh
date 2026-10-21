#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-or-later
# Read-only root diagnosis. Writes only into $1.
set -u; O=$1; mkdir -p $O/acpi
dmidecode > $O/dmidecode.txt 2>&1
lspci -vvv -nn -s 03:00.0 > $O/lspci-cam-root.txt 2>&1
lspci -vvv -nn -s 00:1d.1 > $O/lspci-rp10-root.txt 2>&1
lspci -xxxx -s 03:00.0 > $O/lspci-cam-cfg.txt 2>&1
cp -r /sys/firmware/acpi/tables/. $O/acpi/ 2>/dev/null
chown -R "${SUDO_UID:-$(id -u)}:${SUDO_GID:-$(id -g)}" "$O"
