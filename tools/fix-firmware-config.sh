#!/bin/sh
# SPDX-License-Identifier: GPL-2.0-only
# Copyright (c) 2026 kaywoz
#
# fix-firmware-config.sh - stop the Pi firmware from pinning the CPU at maximum speed.
#
# The rpi5-uefi firmware card ships `force_turbo=1` in its config.txt. The firmware then
# reports min = max frequency (2.4 GHz), so Linux cpufreq has nothing to scale between and
# no governor can lower the clock. This comments that line out on the firmware SD card,
# keeping a backup. Run as root on a booted MOS, then reboot.
#
# Usage: sh fix-firmware-config.sh [--check] [--restore] [--dev DEVICE] [--dir DIR]
#   --check     only report whether force_turbo is set, change nothing
#   --restore   put back the newest backup of config.txt
#   --dev DEV   firmware card partition (default: the one labelled RPIFW, else /dev/mmcblk0p1)
#   --dir DIR   use an already mounted firmware card (or any folder holding config.txt)
set -eu

DEV=""
DIR=""
MODE=fix

say() { printf '==> %s\n' "$*"; }
die() { printf 'ERROR: %s\n' "$*" >&2; exit 1; }
usage() {
  cat <<'USAGE'
Usage: sh fix-firmware-config.sh [--check] [--restore] [--dev DEVICE] [--dir DIR]
  --check     only report whether force_turbo is set, change nothing
  --restore   put back the newest backup of config.txt
  --dev DEV   firmware card partition (default: label RPIFW, else /dev/mmcblk0p1)
  --dir DIR   use an already mounted firmware card (or any folder holding config.txt)
USAGE
}

while [ $# -gt 0 ]; do
  case "$1" in
    --check)   MODE=check ;;
    --restore) MODE=restore ;;
    --dev)     [ $# -ge 2 ] || die "--dev needs a device"; DEV=$2; shift ;;
    --dir)     [ $# -ge 2 ] || die "--dir needs a folder"; DIR=$2; shift ;;
    -h|--help) usage; exit 0 ;;
    *)         usage; die "unknown option: $1" ;;
  esac
  shift
done

[ "$(id -u)" = 0 ] || die "run as root"

MOUNTED_BY_US=""
cleanup() {
  if [ -n "$MOUNTED_BY_US" ]; then
    sync
    umount "$MOUNTED_BY_US" 2>/dev/null && rmdir "$MOUNTED_BY_US" 2>/dev/null || \
      printf 'WARNING: could not unmount %s, run: umount %s\n' "$MOUNTED_BY_US" "$MOUNTED_BY_US" >&2
  fi
}
trap cleanup EXIT

# 1. find the firmware card
if [ -z "$DIR" ]; then
  if [ -z "$DEV" ]; then
    DEV=$(blkid -L RPIFW 2>/dev/null || true)
    [ -n "$DEV" ] || DEV=/dev/mmcblk0p1
  fi
  [ -b "$DEV" ] || die "$DEV is not a block device (use --dev, or --dir if it is already mounted)"
  DIR=$(awk -v d="$DEV" '$1==d{print $2; exit}' /proc/mounts)
  if [ -n "$DIR" ]; then
    say "$DEV is already mounted at $DIR (will leave it mounted)"
  else
    DIR=$(mktemp -d /tmp/mos-rpi5-fw.XXXXXX)
    mount -t vfat "$DEV" "$DIR" || die "could not mount $DEV"
    MOUNTED_BY_US=$DIR
    say "mounted $DEV at $DIR"
  fi
fi
CFG=$DIR/config.txt
[ -f "$CFG" ] || die "$CFG not found: is this the firmware card?"

PAT='^[[:space:]]*force_turbo[[:space:]]*=[[:space:]]*1[[:space:]]*$'

case "$MODE" in
  check)
    if grep -Eq "$PAT" "$CFG"; then
      say "force_turbo=1 is SET in $CFG (CPU pinned at maximum)"
    else
      say "force_turbo=1 is not set in $CFG"
    fi
    ;;
  restore)
    BAK=$(ls -1 "$CFG".bak.* 2>/dev/null | sort | tail -n 1 || true)
    [ -n "$BAK" ] || die "no backup found next to $CFG"
    cp "$BAK" "$CFG"
    say "restored $CFG from $BAK"
    ;;
  fix)
    if ! grep -Eq "$PAT" "$CFG"; then
      say "force_turbo=1 is not set in $CFG, nothing to do"
    else
      BAK=$CFG.bak.$(date +%Y%m%d%H%M%S)
      cp "$CFG" "$BAK"
      sed -E "s/($PAT)/# \1  # disabled by mos-rpi5/" "$CFG" > "$CFG.new" && mv "$CFG.new" "$CFG"
      grep -Eq "$PAT" "$CFG" && die "edit failed, original kept as $BAK"
      say "commented out force_turbo=1 (backup: $BAK)"
      grep -n 'force_turbo' "$CFG" || true
      echo
      echo "Reboot to apply. Afterwards check that the frequency range is no longer a single value:"
      echo "  grep . /sys/devices/system/cpu/cpufreq/policy0/{scaling_governor,cpuinfo_min_freq,cpuinfo_max_freq,scaling_cur_freq}"
    fi
    ;;
esac
