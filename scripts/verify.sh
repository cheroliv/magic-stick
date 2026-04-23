#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
BUILD_DIR="${PROJECT_DIR}/build"

usage() {
    echo "Usage: $0 [ISO_FILE]"
    echo ""
    echo "Verify the Magic Stick ISO."
    echo ""
    echo "Arguments:"
    echo "  ISO_FILE    Path to ISO file (default: latest in build/)"
    echo ""
    echo "Checks performed:"
    echo "  - ISO file exists and is readable"
    echo "  - ISO size is reasonable (> 500MB)"
    echo "  - ISO contains boot files (vmlinuz, initrd)"
    echo "  - ISO is bootable (has GRUB or syslinux)"
}

ISO_FILE="${1:-}"

if [[ -z "$ISO_FILE" ]]; then
    ISO_FILE=$(ls -t "${BUILD_DIR}"/magic_stick_*.iso 2>/dev/null | head -1)
fi

if [[ -z "$ISO_FILE" ]] || [[ ! -f "$ISO_FILE" ]]; then
    echo "ERROR: No ISO file found"
    echo "Run scripts/build.sh first."
    exit 1
fi

echo "=== Magic Stick ISO Verification ==="
echo "File: ${ISO_FILE}"
echo ""

echo "[1/5] Checking file exists..."
echo "  OK: File found"

echo "[2/5] Checking file size..."
ISO_SIZE=$(stat -c%s "$ISO_FILE" 2>/dev/null || stat -f%z "$ISO_FILE" 2>/dev/null)
ISO_SIZE_HUMAN=$(du -h "$ISO_FILE" | cut -f1)
MIN_SIZE=$((500 * 1024 * 1024))

if [[ "$ISO_SIZE" -gt "$MIN_SIZE" ]]; then
    echo "  OK: ${ISO_SIZE_HUMAN}"
else
    echo "  WARNING: ISO is smaller than expected (${ISO_SIZE_HUMAN})"
fi

echo "[3/5] Checking boot files (vmlinuz, initrd)..."
BOOT_FILES_FOUND=false
if isoinfo -i "$ISO_FILE" -l 2>/dev/null | grep -q "vmlinuz"; then
    echo "  OK: vmlinuz found"
    BOOT_FILES_FOUND=true
else
    echo "  WARNING: vmlinuz not found in ISO"
fi

if isoinfo -i "$ISO_FILE" -l 2>/dev/null | grep -q "initrd"; then
    echo "  OK: initrd found"
    BOOT_FILES_FOUND=true
else
    echo "  WARNING: initrd not found in ISO"
fi

echo "[4/5] Checking bootloader..."
if isoinfo -i "$ISO_FILE" -l 2>/dev/null | grep -q -E "(grub|syslinux|isolinux)"; then
    echo "  OK: Bootloader found"
else
    echo "  WARNING: No standard bootloader found"
fi

echo "[5/5] Checking squashfs..."
if isoinfo -i "$ISO_FILE" -l 2>/dev/null | grep -q "filesystem.squashfs"; then
    echo "  OK: filesystem.squashfs found"
else
    echo "  WARNING: No squashfs filesystem found"
fi

echo ""
echo "=== Verification complete ==="
echo "ISO: ${ISO_FILE}"
echo "Size: ${ISO_SIZE_HUMAN}"