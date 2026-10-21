#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-or-later
# Unload macbook91-facetimehd and clear the temporary firmware search path.
rmmod macbook91_facetimehd; rc=$?
echo -n "" > /sys/module/firmware_class/parameters/path
echo "rmmod rc=$rc"
