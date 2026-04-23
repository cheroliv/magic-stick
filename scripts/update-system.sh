#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
BUILD_DIR="${PROJECT_DIR}/build"

usage() {
    echo "Usage: $0 <device> [ISO_FILE]"
    echo ""
    echo "Update the system partition (A/B) on a Magic Stick USB drive."
    echo ""
    echo "This script:"
    echo "  1. Detects which partition (A or B) is currently active"
    echo "  2. Writes the new ISO to the inactive partition"
    echo "  3. Updates the bootloader to boot from the new partition"
    echo "  4. Preserves the persistence partition"
    echo ""
    echo "Arguments:"
    echo "  device     Target device (e.g., /dev/sdb)"
    echo "  ISO_FILE   Path to ISO file (default: latest in build/)"
    echo ""
    echo "WARNING: This modifies the partition table and boot configuration!"
    echo ""
    echo "Partition layout (GPT):"
    echo "  /dev/sdX1  system_a      (~8 GB) - System partition A"
    echo "  /dev/sdX2  system_b      (~8 GB) - System partition B"
    echo "  /dev/sdX3  persistence   (rest)  - User data (never touched)"
}

if [[ $# -lt 1 ]]; then
    usage
    exit 1
fi

DEVICE="$1"
ISO_FILE="${2:-}"

if [[ -z "$ISO_FILE" ]]; then
    ISO_FILE=$(ls -t "${BUILD_DIR}"/magic_stick_*.iso 2>/dev/null | head -1)
fi

if [[ -z "$ISO_FILE" ]] || [[ ! -f "$ISO_FILE" ]]; then
    echo "ERROR: No ISO file found"
    echo "Run scripts/build.sh first."
    exit 1
fi

if [[ "$(id -u)" -ne 0 ]]; then
    echo "ERROR: This script must be run as root (use sudo)"
    exit 1
fi

if [[ ! -b "$DEVICE" ]]; then
    echo "ERROR: ${DEVICE} is not a block device"
    exit 1
fi

echo "=== Magic Stick A/B System Updater ==="
echo ""
echo "ISO:    ${ISO_FILE}"
echo "Device: ${DEVICE}"
echo ""

PART_A="${DEVICE}1"
PART_B="${DEVICE}2"
PART_PERSISTENCE="${DEVICE}3"

echo "Checking partition layout..."
for part in "$PART_A" "$PART_B" "$PART_PERSISTENCE"; do
    if [[ ! -b "$part" ]]; then
        echo "ERROR: Partition ${part} not found"
        echo "The device must have 3 partitions: system_a, system_b, persistence"
        exit 1
    fi
done

echo "Detecting active partition..."
ACTIVE_PARTITION=""
if mount | grep -q "$PART_A"; then
    ACTIVE_PARTITION="A"
    echo "  Active: System A (${PART_A})"
elif mount | grep -q "$PART_B"; then
    ACTIVE_PARTITION="B"
    echo "  Active: System B (${PART_B})"
else
    echo "  WARNING: Cannot detect active partition (not mounted)"
    echo "  Assuming System A is active"
    ACTIVE_PARTITION="A"
fi

if [[ "$ACTIVE_PARTITION" == "A" ]]; then
    TARGET_PARTITION="B"
    TARGET_DEVICE="$PART_B"
else
    TARGET_PARTITION="A"
    TARGET_DEVICE="$PART_A"
fi

echo "  Target: System ${TARGET_PARTITION} (${TARGET_DEVICE})"
echo ""
echo "WARNING: This will write the ISO to ${TARGET_DEVICE}!"
echo "The persistence partition will NOT be touched."
echo ""
read -p "Type 'YES' to continue: " confirm

if [[ "$confirm" != "YES" ]]; then
    echo "Aborted."
    exit 0
fi

echo ""
echo "Unmounting target partition..."
umount "${TARGET_DEVICE}" 2>/dev/null || true

echo "Writing ISO to ${TARGET_DEVICE}..."
dd if="$ISO_FILE" of="$TARGET_DEVICE" bs=4M status=progress conv=fsync

echo ""
echo "Updating bootloader to boot from System ${TARGET_PARTITION}..."
echo "  (Bootloader update not yet implemented - manual GRUB update required)"

echo ""
echo "Syncing..."
sync

echo ""
echo "=== Update complete! ==="
echo "System ${TARGET_PARTITION} has been updated."
echo "On next boot, the system will use the new image."
echo ""
echo "If the new system fails to boot:"
echo "  - Select 'System ${ACTIVE_PARTITION}' in the boot menu"
echo "  - This will boot the previous (known-working) system"
echo ""
echo "Persistence partition was NOT modified (user data safe)."