# Boot recipe

Boot chain: Pi ROM → EEPROM bootloader → UEFI (rpi5-uefi, internal SD) → GRUB (MOS ESP/partition) → kernel `/image` + initrd `/rootfs` (+ `/rp1extra.cpio`) → MOS `init`.

MOS partition layout (mounted at `/boot` once running): `image`, `rootfs` (xz cpio, used as initrd), `drivers` (squashfs with `/lib/modules` and firmware), `grub/grub.cfg`, `bcm2712-rpi-5-b.dtb` (C0), `bcm2712-d-rpi-5-b.dtb` (D0).

## 1. UEFI

Device Tree mode (menu path in the README). ACPI works for booting but hides everything behind a PCIe switch.

## 2. Early RP1 modules

`init` finds the media by label `MOS`, *then* mounts `drivers`. In DT mode the USB controller is on RP1, so its modules must load before that. `tools/rp1build.py` reads `init` from `rootfs`, patches it, and writes a small extra cpio that the kernel overlays on `rootfs`. The patched `init`:

- loads the modules with `insmod`, in the order given, before the media search
- waits 40 s instead of 15 s for the media
- sends its output to HDMI (`/dev/tty1`) instead of the serial console
- on failure prints dmesg/lsmod/PCI/block info and saves dmesg to the firmware SD if present

Run on a booted MOS (module order matters: `insmod` doesn't resolve dependencies and `modprobe` can't be used yet; `irq-bcm2712-mip` goes last):

```sh
python3 -I /boot/rp1build.py /boot/rootfs /boot/rp1extra.cpio \
  $(modinfo -n pinctrl-brcmstb) $(modinfo -n pinctrl-brcmstb-bcm2712) \
  $(modinfo -n gpio-brcmstb) $(modinfo -n clk-rp1) $(modinfo -n pinctrl-rp1) \
  $(modinfo -n rp1-pci) \
  $(modprobe --show-depends sdhci-brcmstb | awk '/^insmod/{print $2}') \
  $(modinfo -n irq-bcm2712-mip)
```

It prints `wrote /boot/rp1extra.cpio … N modules` listing what it packed.

## 3. GRUB

Add the entry from `grub/grub.cfg.example` and set `set default=<its index>` (menu entries are numbered from 0). Keep the old entry as a fallback. Over a KVM the keyboard often doesn't work in GRUB, so rely on the default.

The `devicetree` line must be the **MOS-built** `bcm2712-d-rpi-5-b.dtb` from the MOS partition. Not the CM5 dtb, and not the dtbs from the rpi5-uefi release (see MISTAKES.md).

## 4. After every MOS update

`rp1extra.cpio` replaces `/init` and carries modules for one kernel. Rebuild it after any kernel, `rootfs` or `drivers` update, otherwise you get "insmod failed" lines or a stuck boot.

## Optional

- CPU temperature: `dtb/` (MOS's dtb has no sensor nodes).
- Fixed MAC for the onboard Ethernet: `python3 -I tools/setmac.py /boot/<dtb> aa:bb:cc:dd:ee:ff` (use a MAC unique to this board).
