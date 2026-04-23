#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
BUILD_DIR="${PROJECT_DIR}/build"

usage() {
    echo "Usage: $0 <device>"
    echo ""
    echo "Flash the Magic Stick ISO to a USB drive."
    echo ""
    echo "Arguments:"
    echo "  device    Target device (e.g., /dev/sdX)"
    echo ""
    echo "WARNING: This will ERASE ALL DATA on the target device!"
    echo ""
    echo "Example:"
    echo "  sudo $0 /dev/sdb"
    echo ""
    echo "First, identify your USB drive with:"
    echo "  lsblk"
}

if [[ $# -lt 1 ]]; then
    usage
    exit 1
fi

DEVICE="$1"

if [[ ! -b "$DEVICE" ]]; then
    echo "ERROR: ${DEVICE} is not a block device"
    exit 1
fi

if [[ "$(id -u)" -ne 0 ]]; then
    echo "ERROR: This script must be run as root (use sudo)"
    exit 1
fi

ISO_FILE=$(ls -t "${BUILD_DIR}"/magic_stick_*.iso 2>/dev/null | head -1)

if [[ -z "$ISO_FILE" ]]; then
    echo "ERROR: No ISO file found in ${BUILD_DIR}/"
    echo "Run scripts/build.sh first."
    exit 1
fi

echo "=== Magic Stick Flasher ==="
echo ""
echo "ISO:    ${ISO_FILE}"
echo "Device: ${DEVICE}"
echo "Size:   $(du -h "$ISO_FILE" | cut -f1)"
echo ""
echo "WARNING: This will ERASE ALL DATA on ${DEVICE}!"
echo ""
read -p "Type 'YES' to continue: " confirm

if [[ "$confirm" != "YES" ]]; then
    echo "Aborted."
    exit 0
fi

echo ""
echo "Checking if ${DEVICE} is mounted..."
if mount | grep -q "$DEVICE"; then
    echo "Unmounting partitions on ${DEVICE}..."
    lsblk -n -o MOUNTPOINT "$DEVICE" | grep -v '^$' | sort -u | while read -r mp; do
        if [[ -n "$mp" ]]; then
            umount "$mp" || true
        fi
    done
fi

echo "Flashing ISO to ${DEVICE}..."
dd if="$ISO_FILE" of="$DEVICE" bs=4M status=progress conv=fsync

echo ""
echo "Syncing..."
sync

echo ""
echo "=== Flash complete! ==="
echo "You can now boot from the USB drive."
echo ""
echo "Next steps for A/B partitioning:"
echo "  sudo ${SCRIPT_DIR}/setup-ab-partitions.sh ${DEVICE}"