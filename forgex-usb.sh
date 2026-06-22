#!/usr/bin/env bash
# forgex-usb.sh — stage a Forge-X (ff5m) install USB for the
# Flashforge Adventurer 5M (non-Pro). Printer self-flashes from USB at
# power-on; this script does not write to the printer over USB or serial.
set -euo pipefail

REPO="DrA1ex/ff5m"
API="https://api.github.com/repos/${REPO}/releases"
ASSET_RE='Adventurer5M-ForgeX-[0-9][^"]*[.]tgz'
LABEL="FORGEX"

TAG=""
DEVICE=""
LIST=0

usage() {
  cat <<'EOF'
forgex-usb.sh — make a Forge-X flash USB for Flashforge Adventurer 5M (non-Pro)

Usage:
  forgex-usb.sh [--tag <version>] [--device <path>] [--list] [--help]

Flags:
  --tag <version>   Pin a release tag (e.g. 1.4.1). Default: latest stable.
  --device <path>   Target removable device (e.g. /dev/sdb, /dev/disk4).
                    Omit to be shown candidates and prompted interactively.
  --list            List candidate removable devices and exit.
  --help            Show this help.

The script stages a FAT32 USB only. The printer flashes itself on next
power-on when the USB is inserted before power. Prerequisite: stock
firmware 2.6.5 - 3.1.5.
EOF
}

while [ $# -gt 0 ]; do
  case "$1" in
    --tag)    TAG="${2:?missing value for --tag}"; shift 2 ;;
    --device) DEVICE="${2:?missing value for --device}"; shift 2 ;;
    --list)   LIST=1; shift ;;
    --help|-h) usage; exit 0 ;;
    *) echo "unknown flag: $1" >&2; usage >&2; exit 2 ;;
  esac
done

# ---- OS detect ----
OS="$(uname -s)"
SILVERBLUE=0
case "$OS" in
  Darwin) PLATFORM=macos ;;
  Linux)
    PLATFORM=linux
    if [ -f /run/ostree-booted ]; then
      SILVERBLUE=1
    elif command -v rpm-ostree >/dev/null 2>&1 && rpm-ostree status >/dev/null 2>&1; then
      SILVERBLUE=1
    fi
    ;;
  *) echo "Unsupported OS: $OS (macOS or Linux only)." >&2; exit 1 ;;
esac

need() { command -v "$1" >/dev/null 2>&1 || { echo "missing dep: $1" >&2; return 1; }; }

need curl

if [ "$PLATFORM" = macos ]; then
  need diskutil
  need shasum
  sha256_of() { shasum -a 256 "$1" | awk '{print $1}'; }
else
  need lsblk
  need findmnt
  need sha256sum
  MISSING=""
  for t in mkfs.vfat wipefs sfdisk mount umount; do
    command -v "$t" >/dev/null 2>&1 || MISSING="$MISSING $t"
  done
  if [ -n "$MISSING" ]; then
    if [ "$SILVERBLUE" = 1 ]; then
      cat >&2 <<EOF
Silverblue detected. Missing disk tools:$MISSING
This script will NOT run \`rpm-ostree install\` for you (it requires a reboot).
Choose one:
  1. Run this script inside a toolbox / distrobox container that has
     dosfstools and util-linux installed, with the USB device available.
  2. Layer the packages on the host yourself, reboot, then re-run:
       rpm-ostree install dosfstools util-linux
       systemctl reboot
No changes were made.
EOF
      exit 1
    fi
    echo "missing dep(s):$MISSING (install dosfstools and util-linux)" >&2
    exit 1
  fi
  sha256_of() { sha256sum "$1" | awk '{print $1}'; }
fi

# ---- list helpers ----
list_devices() {
  if [ "$PLATFORM" = macos ]; then
    diskutil list external physical
  else
    lsblk -dpno NAME,SIZE,RM,TRAN,TYPE,MODEL | awk '$5=="disk" && ($3==1 || $4=="usb")'
  fi
}

is_system_disk() {
  local dev="$1"
  if [ "$PLATFORM" = macos ]; then
    local root_whole
    root_whole="$(diskutil info / 2>/dev/null | awk -F': *' '/Part of Whole/{print $2; exit}')"
    [ -n "$root_whole" ] && [ "$dev" = "/dev/$root_whole" ] && return 0
    diskutil info "$dev" 2>/dev/null | grep -Eq 'Internal:[[:space:]]+Yes' && return 0
    return 1
  else
    local src parent
    for mp in / /boot /boot/efi; do
      src="$(findmnt -no SOURCE "$mp" 2>/dev/null || true)"
      [ -n "$src" ] && [ -b "$src" ] || continue
      parent="$(lsblk -no PKNAME "$src" 2>/dev/null | head -1)"
      [ -n "$parent" ] && [ "/dev/$parent" = "$dev" ] && return 0
      [ "$src" = "$dev" ] && return 0
    done
    return 1
  fi
}

if [ "$LIST" = 1 ]; then list_devices; exit 0; fi

# ---- resolve release ----
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

if [ -n "$TAG" ]; then
  URL="${API}/tags/${TAG}"
else
  URL="${API}/latest"
fi

echo "Querying ${URL}"
if ! curl -fsSL -H "Accept: application/vnd.github+json" "$URL" -o "$TMP/release.json"; then
  echo "release lookup failed (tag '${TAG:-latest}' not found?)" >&2
  exit 1
fi

VER="$(awk -F'"' '/"tag_name":/{print $4; exit}' "$TMP/release.json")"
[ -n "$VER" ] || { echo "could not parse tag_name from API response" >&2; exit 1; }

# Extract the non-Pro asset's url / digest / size / name in one pass.
# The asset object starts at the first matching "name": line and ends at the
# next "name": line in the JSON stream.
ASSET_LINE="$(awk -v re="$ASSET_RE" '
  /"name":/ {
    if (capture) { capture=0 }
    if (match($0, "\"name\": \"" re "\"") && !found) {
      capture=1; found=1
      match($0, /"name": "[^"]+"/); n=substr($0, RSTART+9, RLENGTH-10)
      next
    }
  }
  capture && /"browser_download_url":/ {
    match($0, /https:[^"]+/); u=substr($0, RSTART, RLENGTH)
  }
  capture && /"digest":/ {
    match($0, /(sha256|sha512|md5):[A-Fa-f0-9]+/); d=substr($0, RSTART, RLENGTH)
  }
  capture && /"size":/ {
    match($0, /[0-9]+/); s=substr($0, RSTART, RLENGTH)
  }
  END { print u "|" d "|" s "|" n }
' "$TMP/release.json")"

DL_URL="${ASSET_LINE%%|*}"
REST="${ASSET_LINE#*|}"
DL_DIGEST="${REST%%|*}"
REST="${REST#*|}"
DL_SIZE="${REST%%|*}"
DL_NAME="${REST#*|}"

[ -n "$DL_URL" ] || { echo "no non-Pro asset (Adventurer5M-ForgeX-*.tgz) in release $VER" >&2; exit 1; }
[ -n "$DL_DIGEST" ] || { echo "release $VER has no asset digest; cannot verify safely" >&2; exit 1; }

ALGO="${DL_DIGEST%%:*}"
HASH="${DL_DIGEST#*:}"
[ "$ALGO" = "sha256" ] || { echo "unsupported digest algorithm: $ALGO" >&2; exit 1; }

echo "Release : $VER"
echo "Asset   : $DL_NAME (${DL_SIZE} bytes)"
echo "URL     : $DL_URL"
echo "SHA-256 : $HASH"

# ---- download ----
IMG="$TMP/$DL_NAME"
echo "Downloading..."
curl -fL --progress-bar -o "$IMG" "$DL_URL"

echo "Verifying SHA-256..."
GOT="$(sha256_of "$IMG")"
if [ "$GOT" != "$HASH" ]; then
  echo "checksum mismatch" >&2
  echo "expected: $HASH" >&2
  echo "got     : $GOT" >&2
  exit 1
fi
echo "OK"

# ---- pick + guard device ----
if [ -z "$DEVICE" ]; then
  echo
  echo "Candidate removable devices:"
  list_devices || true
  echo
  printf "Enter target device path (e.g. /dev/sdb, /dev/disk4): "
  read -r DEVICE </dev/tty
fi

[ -n "$DEVICE" ] || { echo "no device given" >&2; exit 1; }

if [ "$PLATFORM" = linux ] && [ ! -b "$DEVICE" ]; then
  echo "$DEVICE is not a block device" >&2; exit 1
fi
if [ "$PLATFORM" = macos ] && ! diskutil info "$DEVICE" >/dev/null 2>&1; then
  echo "$DEVICE is not recognized by diskutil" >&2; exit 1
fi

if is_system_disk "$DEVICE"; then
  echo "REFUSING: $DEVICE backs the system / boot disk." >&2
  exit 1
fi

# ---- confirm ----
echo
echo "About to ERASE $DEVICE and write Forge-X $VER to a fresh FAT32 partition (label: $LABEL)."
if [ "$PLATFORM" = macos ]; then
  diskutil info "$DEVICE" | grep -E 'Device / Media Name|Disk Size|Removable Media|Protocol|Device Location' || true
else
  lsblk -dpno NAME,SIZE,MODEL,TRAN "$DEVICE"
fi
printf 'Type ERASE to continue: '
read -r CONFIRM </dev/tty
[ "$CONFIRM" = "ERASE" ] || { echo "Aborted."; exit 1; }

RENAMED="Adventurer5M-ForgeX-${VER}.tgz"

# ---- format + copy ----
if [ "$PLATFORM" = macos ]; then
  diskutil unmountDisk "$DEVICE" >/dev/null 2>&1 || true
  diskutil eraseDisk MS-DOS "$LABEL" MBR "$DEVICE"
  PART="${DEVICE}s1"
  MNT="$(diskutil info "$PART" 2>/dev/null | awk -F': *' '/Mount Point/{print $2; exit}')"
  if [ -z "${MNT:-}" ] || [ ! -d "$MNT" ]; then
    diskutil mount "$PART"
    MNT="$(diskutil info "$PART" | awk -F': *' '/Mount Point/{print $2; exit}')"
  fi
  cp "$IMG" "$MNT/$RENAMED"
  sync
  diskutil eject "$DEVICE"
else
  for p in "${DEVICE}"?*; do [ -b "$p" ] && umount "$p" 2>/dev/null || true; done
  wipefs -a "$DEVICE" >/dev/null
  echo ',,c,*' | sfdisk "$DEVICE" >/dev/null
  partprobe "$DEVICE" 2>/dev/null || blockdev --rereadpt "$DEVICE" 2>/dev/null || true
  udevadm settle 2>/dev/null || sleep 1
  if [[ "$DEVICE" =~ [0-9]$ ]]; then PART="${DEVICE}p1"; else PART="${DEVICE}1"; fi
  [ -b "$PART" ] || { echo "partition $PART did not appear" >&2; exit 1; }
  mkfs.vfat -F 32 -n "$LABEL" "$PART" >/dev/null
  MNT="$(mktemp -d)"
  mount "$PART" "$MNT"
  cp "$IMG" "$MNT/$RENAMED"
  sync
  umount "$MNT"
  rmdir "$MNT"
fi

cat <<EOF

Done. USB labeled $LABEL contains:
  $RENAMED  ($VER)

On the printer:
  1. Stock firmware MUST be 2.6.5 - 3.1.5. Confirm before continuing.
  2. Power the printer OFF.
  3. Insert the USB drive.
  4. Power the printer ON. It will auto-install the update; wait for the
     completion message at the bottom of the screen.
  5. Eject the USB drive and reboot the printer.
EOF
