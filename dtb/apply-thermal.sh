#!/bin/sh
# Add the CPU thermal nodes to a MOS-built bcm2712-d-rpi-5-b.dtb without kernel sources.
# Needs fdtput (package: device-tree-compiler), so run it on a PC, then copy the result to /boot.
# Usage: apply-thermal.sh in.dtb out.dtb
set -e
[ $# -eq 2 ] || { echo "usage: $0 in.dtb out.dtb"; exit 1; }
cp "$1" "$2"
S=/soc@107c000000/avs-monitor@7d542000
fdtput -c "$2" $S
fdtput -t s "$2" $S compatible "brcm,bcm2711-avs-monitor" syscon simple-mfd
fdtput -t x "$2" $S reg 7d542000 f00
fdtput -t s "$2" $S status okay
fdtput -c "$2" $S/thermal
fdtput -t s "$2" $S/thermal compatible "brcm,bcm2711-thermal"
fdtput -t x "$2" $S/thermal '#thermal-sensor-cells' 0
fdtput -t x "$2" $S/thermal phandle 53        # must be an unused phandle; 0x52 was the highest in the tested dtb
fdtput -c "$2" /thermal-zones
fdtput -c "$2" /thermal-zones/cpu-thermal
fdtput -t x "$2" /thermal-zones/cpu-thermal polling-delay-passive 3e8
fdtput -t x "$2" /thermal-zones/cpu-thermal polling-delay 3e8
fdtput -t x "$2" /thermal-zones/cpu-thermal coefficients fffffdda 6ddd0
fdtput -t x "$2" /thermal-zones/cpu-thermal thermal-sensors 53
fdtput -c "$2" /thermal-zones/cpu-thermal/trips
fdtput -c "$2" /thermal-zones/cpu-thermal/trips/cpu-crit
fdtput -t x "$2" /thermal-zones/cpu-thermal/trips/cpu-crit temperature 1adb0
fdtput -t x "$2" /thermal-zones/cpu-thermal/trips/cpu-crit hysteresis 0
fdtput -t s "$2" /thermal-zones/cpu-thermal/trips/cpu-crit type critical
fdtput -t s "$2" /__symbols__ thermal $S/thermal
fdtput -t s "$2" /__symbols__ avs_monitor $S
echo "wrote $2"
