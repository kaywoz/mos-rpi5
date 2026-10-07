# Mistakes and misunderstandings

Keep this file. Whenever a belief turns out wrong, add an entry (newest first) so the next reader doesn't repeat it. Format: what we thought, what was true, how we found out, lesson.

## 2026-10-07: analysed the wrong dtb

- **Thought:** the file named `bcm2712-d-rpi-5-b.dtb` we were looking at was the one MOS loads, and it already had the CPU sensor nodes.
- **True:** two different files share that name. The 78 KB one (md5 `1be945bb…`) comes from the rpi5-uefi (RPI5_D0) firmware release and has `avs-monitor`, `cpu-thermal` and a fan node. The one MOS builds and the Pi loads (22 KB, md5 `b26294bd…`) has none of them.
- **Found by:** `md5sum /boot/bcm2712-d-rpi-5-b.dtb` on the Pi, compared with the earlier upload.
- **Lesson:** compare md5 of the file on the device before reading anything into a same-named file.

## 2026-10-07: wrong thermal driver name

- **Thought:** the Pi 5 sensor needs `brcmstb_thermal` / `brcm,avs-tmon-bcm2712`.
- **True:** it uses `bcm2711_thermal` (`brcm,bcm2711-thermal`) behind an `avs-monitor` syscon node at `0x7d542000`. MOS already ships that driver as a module; only the dtb nodes were missing.
- **Found by:** reading Raspberry Pi's kernel source (`bcm2712-ds.dtsi`, `bcm2711_thermal.c`, `Kconfig`), then testing the patched dtb.
- **Lesson:** check the source before naming a driver or compatible string in a bug report.

## 2026-10-07: a command that could not show the answer

- **Thought:** `find /proc/device-tree -iname '*thermal*'` printing nothing meant no thermal nodes.
- **True:** `/proc/device-tree` is a symlink and `find` doesn't follow a symlink given as the start path. (The conclusion happened to be right; the check was not.)
- **Found by:** re-checking with `ls /sys/firmware/devicetree/base | grep -i thermal`.
- **Lesson:** use `/sys/firmware/devicetree/base` (or a trailing slash) when listing the live DT.

## 2026-10-06: "the RP1 drivers aren't in the kernel"

- **Thought:** a `strings` search of the kernel `Image` found no RP1 drivers, so they were missing.
- **True:** they are modules (`rp1-pci`, `clk-rp1`, `pinctrl-rp1`, …) in the `drivers` squashfs, not in the `Image`.
- **Found by:** `modules.builtin` and `find /lib/modules`.
- **Lesson:** built-in vs module: check `modules.builtin` and `/lib/modules`, not the image.

## 2026-10-06: `init` output expected on HDMI

- **Thought:** `init`'s error messages would show on the screen.
- **True:** `init` writes to the last `console=` (serial `ttyAMA10`), so the HDMI screen stayed silent.
- **Found by:** nothing visible on HDMI while the boot was clearly running.
- **Lesson:** `rp1build.py` now redirects `init` to `/dev/tty1`.

## 2026-10-06: scripts kept in `/tmp`

- **Thought:** helper scripts in `/tmp` would survive a reboot.
- **True:** `/tmp` is RAM on MOS; they vanished on every boot.
- **Lesson:** keep scripts and outputs on the MOS partition (`/boot`).

## 2026-10-06: stray `devicetree` line in `grub.cfg`

- **Thought:** a black screen after GRUB meant a kernel or firmware problem.
- **True:** a `devicetree` line pointing at the CM5 dtb was left active in ACPI mode. Commenting it out booted MOS.
- **Lesson:** the `devicetree` line must match the mode (none for ACPI, the MOS-built Pi 5 dtb for DT mode).

## 2026-10-06: expected NVMe behind the switch to show up under ACPI

- **Thought:** the X1004's NVMe drives would appear as in other OSes.
- **True:** the firmware's ACPI tables describe only PCI bus 00, so nothing behind the ASM1182e switch enumerates.
- **Lesson:** use Device Tree mode for PCIe switch boards.

## Assumptions not verified yet

- Board stepping: the D0 dtb booted, so the board is assumed to be D0.
- That a C0 dtb on D0 silicon panics early: seen as a risk, not tested.
- That MOS keys its network settings to the MAC (the orphaned `eth0` suggests it).
- That a udev rule in `/boot/optional/udev` would run early enough to set the MAC.
- Whether mainline already has the BCM2712 thermal nodes upstream (the MOS-built dtb lacks them).
- The fan path (RP1 PWM + `pwm-fan`).
