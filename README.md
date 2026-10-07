# MOS on Raspberry Pi 5 (UEFI, NVMe behind a PCIe switch)

Unofficial notes, scripts and a dtb patch for booting [MOS](https://mos-official.net) on a Raspberry Pi 5 via UEFI, including two NVMe drives on a Geekworm X1004 (ASM1182e PCIe switch). Tested October 2026.

## Status

| Feature | State |
|---|---|
| Boot MOS from USB | works (UEFI **Device Tree** mode + early RP1 modules) |
| 2 NVMe behind the X1004 switch | works in Device Tree mode; invisible in ACPI mode. ~323 MB/s measured (Gen2 x1, shared) |
| RP1 USB, KVM keyboard | works |
| Onboard Ethernet | works, but gets a random MAC every boot unless fixed ([issue 7](docs/known-issues.md)) |
| CPU temperature | works with the dtb patch; MOS's own dtb has no sensor nodes |
| Fan control | not working / untested (no RP1 PWM node in MOS's dtb) |

Tested on: Pi 5 8 GB (booted with the D0 dtb, stepping not verified), Geekworm X1004, MOS kernel 6.18.55-mos, rpi5-uefi D0 build (NumberOneGit).

## Quick start

1. **Hardware:** FAT32 SD in the Pi's internal slot with the [rpi5-uefi](https://github.com/NumberOneGit/rpi5-uefi) D0 firmware. MOS on a USB drive (ext4 label `MOS` + small vfat ESP), as in the MOS ARM docs.
2. **UEFI:** Device Manager → Raspberry Pi Configuration → ACPI / Device Tree → **Device Tree**.
3. **Build the extra initrd** on a running MOS (first boot in ACPI mode is fine): see [docs/boot-recipe.md](docs/boot-recipe.md). Output: `/boot/rp1extra.cpio`.
4. **GRUB:** add the entry from [grub/grub.cfg.example](grub/grub.cfg.example) and make it the default.
5. Optional: CPU temperature ([dtb/](dtb/)) and a fixed MAC ([tools/setmac.py](tools/setmac.py)).

## Why so much? (3 lines)

- ACPI mode exposes only PCI bus 00, so a PCIe switch's downstream NVMe never enumerates. Device Tree mode fixes that.
- In DT mode MOS's USB ports sit behind RP1, whose drivers are modules in the `drivers` squashfs that `init` can't mount until it has found the media. The extra initrd loads them first.
- MOS's own dtb is needed (it has the labels `rp1-pci` needs), but it lacks the CPU sensor nodes and a MAC address.

If the devs build the RP1 drivers in (`=y`) the extra initrd goes away entirely.

## Contents

| Path | What |
|---|---|
| [docs/boot-recipe.md](docs/boot-recipe.md) | the boot recipe, step by step |
| [docs/known-issues.md](docs/known-issues.md) | symptom, cause, fix |
| [MISTAKES.md](MISTAKES.md) | what we got wrong and corrected (read before trusting a claim) |
| [tools/rp1build.py](tools/rp1build.py) | builds `rp1extra.cpio` |
| [tools/setmac.py](tools/setmac.py) | writes a fixed MAC into the dtb |
| [dtb/](dtb/) | CPU thermal patch (dts snippet + script for a prebuilt dtb) |
| [grub/grub.cfg.example](grub/grub.cfg.example) | working GRUB entry |
| [LICENSE](LICENSE), [.gitignore](.gitignore) | MIT; keeps generated dtbs/cpio out of git |

## License

[MIT](LICENSE), except `dtb/`: the thermal nodes are derived from Raspberry Pi's kernel tree and keep that tree's license (GPL-2.0).
