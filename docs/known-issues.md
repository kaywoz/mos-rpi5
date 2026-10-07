# Known issues: symptom, cause, fix

| # | Symptom | Cause | Fix |
|---|---|---|---|
| 1 | Stays at the Pi logo; bootloader log lists the MOS partitions (`trying partition 1 … 'MOS'`) then `failed to open partition 2` | MOS image booted directly; the Pi ROM can't boot it without UEFI firmware | Put rpi5-uefi on a FAT32 SD in the internal slot, MOS on USB |
| 2 | UEFI and GRUB work, then a black screen with a blinking cursor, no network | A `devicetree` line in `grub.cfg` pointed at the wrong dtb (the CM5 one) with UEFI in ACPI/Both mode | ACPI mode: remove the `devicetree` line. DT mode: use the MOS-built `bcm2712-d-rpi-5-b.dtb` |
| 3 | `lspci` shows only the switch upstream port (`0001:00:00.0`), `lsblk` shows no NVMe | ACPI mode: the firmware describes only PCI bus 00, so nothing behind the X1004's ASM1182e is enumerated | UEFI → Device Tree mode (NVMe then appears on buses 01-04) |
| 4 | DT mode: `init` stops with `MOS boot device with label: MOS not found`; dmesg: `rp1_pci … Failed to allocate MSI-X vectors (-524)` | `irq-bcm2712-mip` (MSI-X) isn't loaded, so RP1 (and the USB drive behind it) never probes | Early-module initrd, MIP loaded last ([boot-recipe](boot-recipe.md)) |
| 5 | DT mode, no GRUB `devicetree`: `OF: resolver: node label 'clk_rp1_xosc' not found in live devicetree symbols table (-22)` | The firmware's built-in DT lacks the labels `rp1-pci`'s overlay needs | `devicetree /bcm2712-d-rpi-5-b.dtb` in GRUB (MOS's own dtb defines them) |
| 6 | No output from `init` on HDMI, can't see why the boot stops | `init` prints to the last `console=` (the serial `ttyAMA10`) | `rp1build.py` redirects `init`'s output to `/dev/tty1` |
| 7 | Onboard `eth0` gets a new MAC every boot; the old one is left orphaned in MOS | `local-mac-address = [00 00 00 00 00 00]` in the dtb. The Pi firmware normally fills it in; UEFI doesn't, so `macb` picks a random one | `tools/setmac.py` writes a fixed MAC per board. Proper fix: MOS sets a stable per-board MAC early |
| 8 | `sensors` shows only the NVMe; `/sys/class/thermal` is empty | MOS-built dtb has no `avs-monitor`/`thermal` node or `cpu-thermal` zone (the dtbs in the rpi5-uefi release do). The driver `bcm2711_thermal` is already a kernel module | `dtb/apply-thermal.sh`, or add `dtb/cpu-thermal.dts.snippet` to the kernel's dts |
| 9 | Boot gets stuck or `insmod failed` lines appear after a MOS update | `rp1extra.cpio` overrides `/init` and carries modules built for the old kernel | Rebuild it after every kernel/`rootfs`/`drivers` update ([procedure](boot-recipe.md)) |
| 10 | NVMe throughput tops out near 400 MB/s | X1004's ASM1182e switch is Gen2 x1, shared by both drives (323 MB/s measured with `dd`) | Expected; a single-NVMe board (e.g. X1002) has no switch |
| 11 | Keyboard dead in GRUB over a KVM, can't press `e` | USB input isn't ready at the GRUB stage | Set `set default=` in `grub.cfg` instead of picking at the menu |
| 12 | Black screen after GRUB, or init error screen, right after changing the UEFI mode | The default GRUB entry doesn't match the mode (the Device Tree entry in ACPI mode, or the stock entry in DT mode) | Change the default *before* switching mode: `--default` before DT, `--stock` before ACPI. If already stuck, set `set default=` in `grub/grub.cfg` from another Linux machine (the MOS USB drive is ext4) |

## Not solved

- Fan: the MOS dtb has no RP1 PWM node or `pwm-fan`; not tested.
- A permanent fix for 4 and 5: build the RP1 drivers in (`=y`) or let `init` load early modules itself.
