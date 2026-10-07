#!/bin/sh
# SPDX-License-Identifier: GPL-2.0-only
# Copyright (c) 2026 kaywoz
#
# install-rp1-boot.sh - prepare MOS on a Raspberry Pi 5 for UEFI Device Tree mode.
#
# Run as root on a booted MOS (first boot: UEFI in ACPI mode, stock GRUB entry).
# It does three things:
#   1. builds /boot/rp1extra.cpio (RP1 modules loaded before MOS looks for its media)
#   2. adds a GRUB entry for it to /boot/grub/grub.cfg (once; a backup is kept)
#   3. optionally makes that entry the default
#
# Usage:  sh install-rp1-boot.sh [--default] [--stock] [--no-grub] [--dtb NAME]
#   --default   make the new GRUB entry the default (do this once UEFI is on Device Tree)
#   --stock     make the first (stock) GRUB entry the default again, e.g. before a MOS update
#   --no-grub   only build rp1extra.cpio, leave grub.cfg alone
#   --dtb NAME  dtb on the MOS partition (default: bcm2712-d-rpi-5-b.dtb)
# Re-run it after every MOS kernel/rootfs/drivers update: the cpio holds modules for one kernel.
set -eu

BOOT=${BOOT:-/boot}
DTB=bcm2712-d-rpi-5-b.dtb
DO_DEFAULT=0
DO_STOCK=0
DO_GRUB=1

say() { printf '==> %s\n' "$*"; }
die() { printf 'ERROR: %s\n' "$*" >&2; exit 1; }
usage() {
  cat <<'USAGE'
Usage: sh install-rp1-boot.sh [--default] [--stock] [--no-grub] [--dtb NAME]
  --default   make the new GRUB entry the default (once UEFI is on Device Tree)
  --stock     make the first (stock) GRUB entry the default again
  --no-grub   only build rp1extra.cpio, leave grub.cfg alone
  --dtb NAME  dtb on the MOS partition (default: bcm2712-d-rpi-5-b.dtb)
USAGE
}

while [ $# -gt 0 ]; do
  case "$1" in
    --default) DO_DEFAULT=1 ;;
    --stock)   DO_STOCK=1 ;;
    --no-grub) DO_GRUB=0 ;;
    --dtb)     [ $# -ge 2 ] || die "--dtb needs a file name"; DTB=$2; shift ;;
    -h|--help) usage; exit 0 ;;
    *)         usage; die "unknown option: $1" ;;
  esac
  shift
done
[ "$DO_DEFAULT" = 1 ] && [ "$DO_STOCK" = 1 ] && die "use either --default or --stock, not both"

CFG=$BOOT/grub/grub.cfg
MARK='# mos-rpi5: rp1 early modules'

set_default() {
  cp "$CFG" "$CFG.bak.$(date +%Y%m%d%H%M%S)"
  if grep -q '^set default=' "$CFG"; then
    sed -i "s/^set default=.*/set default=$1/" "$CFG"
  else
    { echo "set default=$1"; cat "$CFG"; } > "$CFG.new" && mv "$CFG.new" "$CFG"
  fi
}
rp1_index() { awk -v m="$MARK" '/^menuentry/{n++} index($0,m)==1{print n+0; exit}' "$CFG"; }

# --stock only touches grub.cfg
if [ "$DO_STOCK" = 1 ]; then
  [ -f "$CFG" ] || die "$CFG not found"
  set_default 0
  say "default GRUB entry is now 0 (stock MOS). Set UEFI back to ACPI before rebooting."
  exit 0
fi

# 1. checks
say "checking the system"
[ "$(id -u)" = 0 ] || die "run as root"
command -v python3 >/dev/null 2>&1 || die "python3 not found"
command -v modinfo >/dev/null 2>&1 || die "modinfo not found"
[ -f "$BOOT/rootfs" ] && [ -f "$BOOT/image" ] || die "$BOOT/rootfs or $BOOT/image missing: is the MOS partition mounted at $BOOT?"
DIR=$(cd "$(dirname "$0")" && pwd)
[ -f "$DIR/rp1build.py" ] || die "rp1build.py must be in the same folder as this script"

# the root filesystem is RAM on MOS: keep the tools on the MOS partition
if [ "$DIR" != "$BOOT/mos-rpi5" ]; then
  mkdir -p "$BOOT/mos-rpi5"
  cp "$DIR/rp1build.py" "$DIR/install-rp1-boot.sh" "$BOOT/mos-rpi5/"
  say "copied the tools to $BOOT/mos-rpi5 (re-run them from there after MOS updates)"
  DIR=$BOOT/mos-rpi5
fi

# 2. find the modules, in load order (insmod does not resolve dependencies; MIP goes last)
say "locating RP1 modules for kernel $(uname -r)"
MODS=""
add_module() {
  p=$(modinfo -n "$1" 2>/dev/null) || p=""
  case "$p" in
    *builtin*) say "$1 is built into this kernel, skipping"; return 0 ;;
  esac
  [ -f "$p" ] || die "module $1 not found for kernel $(uname -r)"
  MODS="$MODS $p"
}
for m in pinctrl-brcmstb pinctrl-brcmstb-bcm2712 gpio-brcmstb clk-rp1 pinctrl-rp1 rp1-pci; do
  add_module "$m"
done
SD=$(modprobe --show-depends sdhci-brcmstb 2>/dev/null | awk '/^insmod/{print $2}') || SD=""
if [ -n "$SD" ]; then MODS="$MODS $SD"; else say "sdhci-brcmstb not found or built in, skipping"; fi
add_module irq-bcm2712-mip
[ -n "$MODS" ] || die "no modules to pack: this kernel may already have everything built in"

# 3. build the extra initrd
say "building $BOOT/rp1extra.cpio"
# shellcheck disable=SC2086
python3 -I "$DIR/rp1build.py" "$BOOT/rootfs" "$BOOT/rp1extra.cpio" $MODS

# 4. GRUB
if [ "$DO_GRUB" = 1 ]; then
  [ -f "$CFG" ] || die "$CFG not found"
  [ -f "$BOOT/$DTB" ] || die "$BOOT/$DTB not found (the MOS-built Pi 5 dtb on the MOS partition)"
  IDX=$(rp1_index)
  if [ -n "$IDX" ]; then
    say "GRUB entry already present (entry $IDX), leaving it as is"
  else
    IDX=$(grep -c '^menuentry' "$CFG" || true)
    cp "$CFG" "$CFG.bak.$(date +%Y%m%d%H%M%S)"
    cat >> "$CFG" <<GRUBEOF

$MARK
menuentry "MOS (RP1 early modules, D0 dtb)" {
  devicetree /$DTB
  linux  /image loglevel=7 ignore_loglevel console=tty1 console=ttyAMA10,115200
  initrd /rootfs /rp1extra.cpio
}
GRUBEOF
    say "added GRUB entry $IDX (backup of grub.cfg kept next to it)"
  fi
  if [ "$DO_DEFAULT" = 1 ]; then
    set_default "$IDX"
    say "default GRUB entry is now $IDX"
  fi
fi

say "done."
if [ "$DO_GRUB" = 1 ] && [ "$DO_DEFAULT" = 0 ]; then
  HINT="
  3. The new GRUB entry is not the default yet. Once UEFI is on Device Tree, run:
     sh $DIR/install-rp1-boot.sh --default"
else
  HINT=""
fi
cat <<MSG

Next:
  1. Reboot and open the UEFI setup (Esc or Del at the Pi logo):
     Device Manager -> Raspberry Pi Configuration -> ACPI / Device Tree -> Device Tree
  2. Save and boot. If the screen goes black after GRUB, UEFI is still in ACPI mode.$HINT

After a MOS update (the cpio must be rebuilt for the new kernel):
  sh $DIR/install-rp1-boot.sh --stock, set UEFI back to ACPI, reboot into stock MOS,
  then sh $DIR/install-rp1-boot.sh --default and set UEFI to Device Tree again.
MSG
