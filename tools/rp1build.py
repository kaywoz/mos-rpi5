#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only
# Copyright (c) 2026 kaywoz
"""rp1build.py - build an extra initrd that loads the Pi 5 RP1 modules before
MOS's init looks for its boot media (needed for UEFI Device Tree mode, where the
USB ports sit behind the RP1 chip).

What it does
  1. Reads the original /init out of the MOS rootfs (xz-compressed newc cpio).
  2. Patches it:
       - sends init's output to HDMI (/dev/tty1) instead of the serial console
       - insmods the given modules, in the order given, before the media search
       - waits 40 s for the media instead of 15 s
       - on failure prints dmesg/lsmod/PCI/block info and, if a FAT SD card
         (/dev/mmcblk0p1) is present, saves dmesg/lsmod there
  3. Writes a small uncompressed cpio holding rp1mods/*.ko.xz plus the patched
     /init. Boot it as a second initrd; the kernel overlays it on top of rootfs.

Usage (run on a booted MOS; paths are the MOS partition mounted at /boot)
  python3 -I /boot/rp1build.py /boot/rootfs /boot/rp1extra.cpio \\
      $(modinfo -n pinctrl-brcmstb) $(modinfo -n pinctrl-brcmstb-bcm2712) \\
      $(modinfo -n gpio-brcmstb) $(modinfo -n clk-rp1) $(modinfo -n pinctrl-rp1) \\
      $(modinfo -n rp1-pci) \\
      $(modprobe --show-depends sdhci-brcmstb | awk '/^insmod/{print $2}') \\
      $(modinfo -n irq-bcm2712-mip)

Module order matters: insmod does not resolve dependencies and modprobe cannot
be used yet (/lib/modules is inside the drivers squashfs, not mounted at this
point). irq-bcm2712-mip goes last. Rebuild after every MOS kernel/rootfs update:
the cpio replaces /init and carries modules for one specific kernel.

GRUB entry:
  menuentry "MOS (RP1 early modules, D0 dtb)" {
    devicetree /bcm2712-d-rpi-5-b.dtb
    linux  /image loglevel=7 ignore_loglevel console=tty1 console=ttyAMA10,115200
    initrd /rootfs /rp1extra.cpio
  }
"""
import lzma
import os
import sys

if len(sys.argv) < 4:
    sys.exit('usage: rp1build.py ROOTFS OUT.cpio MODULE.ko.xz [MODULE.ko.xz ...]')
rootfs, out_path, *mods = sys.argv[1:]

pad = lambda k: (4 - k % 4) % 4

# --- 1. read the original init from the rootfs (newc cpio, xz compressed) ---
f = lzma.open(rootfs, 'rb')
src = None
while True:
    r = f.read(4)
    if not r:
        break
    if r == b'\0\0\0\0':          # padding between concatenated archives
        continue
    r += f.read(2)
    if r != b'070701':
        sys.exit('bad cpio magic in rootfs')
    h = f.read(104)
    v = [int(h[i * 8:(i + 1) * 8], 16) for i in range(13)]
    size, namesize = v[6], v[11]
    name = f.read(namesize)[:-1].decode('utf8', 'replace')
    f.read(pad(110 + namesize))
    data = f.read(size)
    f.read(pad(size))
    if name == 'init':
        src = data.decode()
        break
    if name == 'TRAILER!!!':
        break
if src is None:
    sys.exit('init not found in rootfs')

# --- 2. patch init ---
A = '# Get device to boot from\n'                                              # insert module loading before this
B = '  /bin/echo "ERROR: MOS boot device with label: $BOOT_LABEL not found"\n'  # extend the error branch
C = '/usr/bin/seq 1 15'                                                       # media search retries
D = '/bin/mount -t devtmpfs none /dev\n'                                      # redirect output after this
assert (src.count(D) == 1 and src.count(A) == 1 and src.count(B) == 1
        and src.count(C) == 1), 'init does not look like the expected MOS init'

load = ('# RP1 early modules (Pi 5 Device Tree boot), added by rp1build\n'
        '/bin/echo "Loading RP1 early modules"\n')
for m in mods:
    b = os.path.basename(m)
    load += '/usr/sbin/insmod /rp1mods/%s 2>&1 || /bin/echo "insmod %s failed (ignored)"\n' % (b, b)
load += '/bin/sleep 5\n\n'

dump = (B +
        '  /bin/echo "--- rp1/usb/msi dmesg ---"\n'
        "  /bin/dmesg | /bin/grep -iE 'rp1|mip|msi|xhci|dwc3|usb|macb|overlay' | /usr/bin/tail -25\n"
        '  /bin/echo "--- lsmod ---"\n'
        '  /usr/sbin/lsmod\n'
        '  /bin/echo "--- pci devices ---"\n'
        '  /bin/ls /sys/bus/pci/devices\n'
        '  /bin/echo "--- block devices ---"\n'
        '  /bin/ls /sys/block\n'
        '  if [ -b /dev/mmcblk0p1 ] ; then\n'
        '    /bin/mkdir -p /mnt/fw\n'
        '    if /bin/mount -t vfat /dev/mmcblk0p1 /mnt/fw ; then\n'
        '      /bin/dmesg > /mnt/fw/dmesg-dt.txt ; /usr/sbin/lsmod > /mnt/fw/lsmod-dt.txt ; /bin/sync ; /bin/umount /mnt/fw\n'
        '      /bin/echo "saved dmesg-dt.txt to the firmware SD card"\n'
        '    fi\n'
        '  fi\n')

src = (src.replace(A, load + A)
          .replace(B, dump)
          .replace(C, '/usr/bin/seq 1 40')
          .replace(D, D + '[ -c /dev/tty1 ] && exec >/dev/tty1 2>&1\n'))


# --- 3. write the extra initrd (uncompressed newc cpio) ---
def ent(name, mode, data=b''):
    nm = name.encode() + b'\0'
    hdr = b'070701' + b''.join(b'%08X' % x for x in
                               [1, mode, 0, 0, 1, 0, len(data), 0, 0, 0, 0, len(nm), 0])
    s = hdr + nm
    s += b'\0' * ((4 - len(s) % 4) % 4)
    s += data
    s += b'\0' * ((4 - len(data) % 4) % 4)
    return s


out = [ent('rp1mods', 0o40755)]
for m in mods:
    with open(m, 'rb') as fh:
        out.append(ent('rp1mods/' + os.path.basename(m), 0o100644, fh.read()))
out.append(ent('init', 0o100755, src.encode()))
out.append(ent('TRAILER!!!', 0))
blob = b''.join(out)
blob += b'\0' * ((512 - len(blob) % 512) % 512)
with open(out_path, 'wb') as fh:
    fh.write(blob)
print('wrote', out_path, len(blob), 'bytes;', len(mods), 'modules:',
      ' '.join(os.path.basename(m) for m in mods))
