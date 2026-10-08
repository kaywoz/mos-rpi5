# Boot recipe

Boot chain: Pi ROM → EEPROM bootloader → UEFI (rpi5-uefi, internal SD) → GRUB (MOS partition) → kernel `/image` + initrd `/rootfs` (+ `/rp1extra.cpio`) → MOS `init`.

MOS partition (mounted at `/boot` once running): `image`, `rootfs` (xz cpio used as initrd), `drivers` (squashfs with `/lib/modules` and firmware), `grub/grub.cfg`, `bcm2712-rpi-5-b.dtb` (C0), `bcm2712-d-rpi-5-b.dtb` (D0). **MOS's root filesystem is RAM**: anything outside `/boot` is gone after a reboot, so the tools live in `/boot/mos-rpi5/`.

## What you run

On a booted MOS (first boot: UEFI in ACPI mode), as root, with `tools/` copied to the Pi:

```sh
cd /root/tools && sh install-rp1-boot.sh --default
```

Then reboot and set UEFI to Device Tree (README, step 3). Flags: `--default` makes the new GRUB entry the default, `--stock` makes the first (stock) entry the default again, `--no-grub` only builds the cpio, `--dtb NAME` picks another dtb.

## What the script does

1. **Checks** root, python3, `modinfo`, and that `/boot` holds `rootfs` and `image`. Copies itself and `rp1build.py` to `/boot/mos-rpi5/`.
2. **Finds the RP1 modules** for the running kernel, in load order: `pinctrl-brcmstb`, `pinctrl-brcmstb-bcm2712`, `gpio-brcmstb`, `clk-rp1`, `pinctrl-rp1`, `rp1-pci`, `sdhci-brcmstb` (plus its dependencies), `irq-bcm2712-mip` last. Order is by hand because `insmod` doesn't resolve dependencies and `modprobe` can't be used before the `drivers` squashfs is mounted. A module that is built in is skipped.
3. **Builds `/boot/rp1extra.cpio`** with `rp1build.py`. It reads `init` out of `rootfs`, patches it, and packs it with the modules. The kernel overlays this second initrd on `rootfs`. The patched `init` loads the modules before the media search, waits 40 s instead of 15, prints to HDMI (`/dev/tty1`) instead of the serial console, and on failure dumps dmesg/lsmod/PCI info (and saves dmesg to the firmware SD if present).
4. **Adds a GRUB entry once** (marker `# mos-rpi5: rp1 early modules`, backup of `grub.cfg` kept) using the MOS-built `bcm2712-d-rpi-5-b.dtb`. See [grub/grub.cfg.example](../grub/grub.cfg.example). It is the MOS dtb from the MOS partition, not the CM5 dtb and not the dtbs from the rpi5-uefi release (see [MISTAKES.md](../MISTAKES.md)).

Running the script again is safe: it rebuilds the cpio and leaves an existing GRUB entry alone.

## After a MOS update

`rp1extra.cpio` replaces `/init` and carries modules for one kernel, so it must be rebuilt for the new kernel. The new modules are only available once the new MOS is running, so: `sh /boot/mos-rpi5/install-rp1-boot.sh --stock`, set UEFI to ACPI, reboot into stock MOS, then `sh /boot/mos-rpi5/install-rp1-boot.sh --default` and set UEFI to Device Tree again. (Not tested on a real update yet. The devs building the RP1 drivers in, `=y`, makes all of this unnecessary.)

## Manual equivalent

Only if you can't use the script (run on a booted MOS):

```sh
python3 -I /boot/mos-rpi5/rp1build.py /boot/rootfs /boot/rp1extra.cpio \
  $(modinfo -n pinctrl-brcmstb) $(modinfo -n pinctrl-brcmstb-bcm2712) \
  $(modinfo -n gpio-brcmstb) $(modinfo -n clk-rp1) $(modinfo -n pinctrl-rp1) \
  $(modinfo -n rp1-pci) \
  $(modprobe --show-depends sdhci-brcmstb | awk '/^insmod/{print $2}') \
  $(modinfo -n irq-bcm2712-mip)
```

Then append the entry from `grub/grub.cfg.example` to `/boot/grub/grub.cfg` and set `set default=<its index>` (entries count from 0).

## Optional

- CPU temperature: [dtb/](../dtb/) (MOS's dtb has no sensor nodes).
- Fixed MAC for the onboard Ethernet: `python3 -I tools/setmac.py /boot/<dtb> aa:bb:cc:dd:ee:ff`, one MAC per board.
- CPU pinned at 2.4 GHz (`force_turbo=1` on the firmware card): `sh tools/fix-firmware-config.sh --check`, then without `--check`, reboot. `--restore` undoes it.
