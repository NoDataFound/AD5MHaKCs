# AD5MHaKCs

Single-purpose USB maker for the [Forge-X](https://github.com/DrA1ex/ff5m) firmware mod on the **Flashforge Adventurer 5M (non-Pro)**.

## What it does

`forgex-usb.sh` stages a FAT32 USB that the printer reads at power-on to flash itself.

1. Queries the GitHub releases API for `DrA1ex/ff5m` (no hardcoded versions).
2. Downloads the non-Pro image (`Adventurer5M-ForgeX-<ver>.tgz`). Does not unpack it.
3. Verifies the SHA-256 against the publisher's asset digest. Aborts on mismatch.
4. Erases the chosen USB and creates a fresh FAT32 partition labeled `FORGEX`.
5. Copies the image to the USB as `Adventurer5M-ForgeX-<ver>.tgz`.

## What it does NOT do

- Does **not** flash the printer. The printer self-installs the image at power-on.
- Does **not** talk to the printer over USB or serial.
- Does **not** auto-select a target disk. You pass `--device` or pick interactively.
- Does **not** touch the system / boot disk.

## Prerequisites

- **Printer stock firmware must be 2.6.5 - 3.1.5.** Downgrade first if needed.
- A USB flash drive you are willing to erase.
- macOS, **or** Linux with `dosfstools` + `util-linux`.

If any tool is missing on Linux, the script will offer to install it via your package manager (`apt`, `dnf`, `yum`, `pacman`, `zypper`, `apk`, or `rpm-ostree`) and prompts before doing so. Use `--no-install` to disable this and fail instead.

### Fedora Silverblue note

Silverblue is immutable. If `dosfstools` is missing, the script will offer to layer it with `rpm-ostree install dosfstools util-linux`, but the layered packages only become available **after a reboot**, so the script then exits and you must re-run it after `systemctl reboot`. No reboot needed if you instead run the script inside a `toolbox` / `distrobox` that already has the tools.

## Usage

```
sudo ./forgex-usb.sh --list                       # show candidate USB devices
sudo ./forgex-usb.sh --device /dev/sdb            # Linux example, latest stable
sudo ./forgex-usb.sh --device /dev/disk4          # macOS example, latest stable
sudo ./forgex-usb.sh --tag 1.4.1 --device /dev/sdb
./forgex-usb.sh --help
```

Flags:

| Flag | Meaning |
|---|---|
| `--tag <ver>` | Pin a release tag. Default: latest stable. |
| `--device <path>` | Target removable device. If omitted, candidates are shown and you are prompted. |
| `--list` | List candidate removable devices and exit. |
| `--no-install` | Do not auto-install missing deps; fail with a message. |
| `--help` | Show help. |

The script requires you to type `ERASE` before it formats anything.

## On the printer

1. Confirm stock firmware is 2.6.5 - 3.1.5.
2. Power the printer **off**.
3. Insert the staged USB.
4. Power **on**. The printer auto-installs from the USB; wait for the completion message.
5. Eject the USB and reboot the printer.

## License

[MIT](LICENSE).
