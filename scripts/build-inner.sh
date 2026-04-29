#!/usr/bin/env bash
set -euo pipefail

PROJECT_DIR="/magic_stick"
BUILD_DIR="${PROJECT_DIR}/build"
CONFIG_DIR="${PROJECT_DIR}/config/live-build"
ISO_NAME="magic_stick_${MAGIC_STICK_VERSION}.iso"

echo "=== Inner build (container) v${MAGIC_STICK_VERSION} ==="

if [[ "${PURGE}" == true ]]; then
    echo "Purging build directory..."
    cd "${BUILD_DIR}" && lb clean --purge 2>/dev/null || true
elif [[ "${CLEAN}" == true ]]; then
    echo "Cleaning build artifacts..."
    cd "${BUILD_DIR}" && lb clean 2>/dev/null || true
fi

if [[ ! -f "${BUILD_DIR}/config/common" ]]; then
    echo "Initializing live-build configuration..."
    cd "${BUILD_DIR}" && lb config \
        --distribution noble \
        --architecture amd64 \
        --binary-images iso-hybrid \
        --bootloader syslinux \
        --syslinux-theme live-build \
        --mode ubuntu \
        --initramfs casper \
        --initsystem systemd \
        --parent-distribution noble \
        --parent-mirror-bootstrap http://archive.ubuntu.com/ubuntu \
        --parent-mirror-binary http://archive.ubuntu.com/ubuntu \
        --mirror-bootstrap http://archive.ubuntu.com/ubuntu \
        --mirror-binary http://archive.ubuntu.com/ubuntu \
        --archive-areas 'main restricted universe multiverse' \
        --bootappend-live 'boot=casper username=magic hostname=magic_stick locales=fr_FR.UTF-8 keyboard-layouts=fr quiet splash' \
        --iso-volume "Magic Stick ${MAGIC_STICK_VERSION}" \
        --iso-publisher 'Magic Stick' \
        --iso-application 'Magic Stick Live System'

    echo "Disabling chroot upgrades..."
    echo "false" > "${BUILD_DIR}/config/chroot_upgrades"
fi

echo "Applying Magic Stick configuration..."
cp -r "${CONFIG_DIR}/package-lists/"* "${BUILD_DIR}/config/package-lists/" 2>/dev/null || true
chmod 644 "${BUILD_DIR}/config/package-lists/"*.list.chroot 2>/dev/null || true

if [[ -d "${CONFIG_DIR}/hooks" ]]; then
    cp -r "${CONFIG_DIR}/hooks/"* "${BUILD_DIR}/config/hooks/" 2>/dev/null || true
    chmod 755 "${BUILD_DIR}/config/hooks/"*.chroot* "${BUILD_DIR}/config/hooks/"*.binary 2>/dev/null || true
fi

if [[ -d "${CONFIG_DIR}/includes.chroot" ]]; then
    cp -r "${CONFIG_DIR}/includes.chroot/"* "${BUILD_DIR}/config/includes.chroot/" 2>/dev/null || true
fi

if [[ -d "${CONFIG_DIR}/includes.binary" ]]; then
    cp -r "${CONFIG_DIR}/includes.binary/"* "${BUILD_DIR}/config/includes.binary/" 2>/dev/null || true
fi

echo "Patching syslinux bootloader templates for Ubuntu 24.04 compatibility..."
BOOTLOADER_DIR="${BUILD_DIR}/config/bootloaders/isolinux"
mkdir -p "${BOOTLOADER_DIR}"

for _f in isolinux.cfg install.cfg menu.cfg stdmenu.cfg live.cfg.in splash.svg.in; do
    _src="/usr/share/live/build/bootloaders/isolinux/${_f}"
    if [ -f "${_src}" ]; then
        cp "${_src}" "${BOOTLOADER_DIR}/"
    else
        echo "WARN: ${_src} not found — skipping"
    fi
done

if [ -f /usr/lib/ISOLINUX/isolinux.bin ]; then
    cp /usr/lib/ISOLINUX/isolinux.bin "${BOOTLOADER_DIR}/isolinux.bin"
elif [ -f /usr/lib/syslinux/isolinux.bin ]; then
    cp /usr/lib/syslinux/isolinux.bin "${BOOTLOADER_DIR}/isolinux.bin"
fi

for _mod in ldlinux.c32 libcom32.c32 libutil.c32 menu.c32 vesamenu.c32; do
    if [ -f "/usr/lib/syslinux/modules/bios/${_mod}" ]; then
        cp "/usr/lib/syslinux/modules/bios/${_mod}" "${BOOTLOADER_DIR}/${_mod}"
    elif [ -f "/usr/lib/syslinux/${_mod}" ]; then
        cp "/usr/lib/syslinux/${_mod}" "${BOOTLOADER_DIR}/${_mod}"
    fi
done

_TMPDIR=$(mktemp -d) && pushd "${_TMPDIR}" > /dev/null && touch .bootlogo_marker && find . | cpio --quiet -o > "${BOOTLOADER_DIR}/bootlogo" 2>/dev/null; popd > /dev/null; rm -rf "${_TMPDIR}"

echo "Patching syslinux boot menu timeout and live.cfg template..."

if [ -f "${BOOTLOADER_DIR}/isolinux.cfg" ]; then
    sed -i 's/^timeout 0/timeout 50/' "${BOOTLOADER_DIR}/isolinux.cfg"
fi

if [ -f "${BOOTLOADER_DIR}/live.cfg.in" ]; then
    sed -i 's|boot=live config ||g' "${BOOTLOADER_DIR}/live.cfg.in"
fi

echo "Patching lb_binary_syslinux for casper and Ubuntu 24.04 compatibility..."
python3 "${CONFIG_DIR}/patches/patch-syslinux.py" || true

echo "Patching lb_binary_iso for xorriso + UEFI support..."
python3 "${CONFIG_DIR}/patches/patch-iso.py" || true

DISK_SCRIPT="/usr/lib/live/build/lb_binary_disk"
if [ -f "${DISK_SCRIPT}" ]; then
    sed -i 's#unmkinitramfs "../../${INITRD}" .#unmkinitramfs "../../${INITRD}" . || true#g' "${DISK_SCRIPT}"
fi

echo "Building ISO... (this will take 30-60 minutes)"
cd "${BUILD_DIR}" && lb build 2>&1

ISO_PATH=$(find "${BUILD_DIR}" -maxdepth 1 \( -name 'live-image-*.iso' -o -name 'binary*.iso' \) 2>/dev/null | head -1 || true)
if [[ -z "${ISO_PATH}" ]]; then
    echo "ERROR: Build failed - no ISO file generated"
    echo "Check build/logs/ for details."
    exit 1
fi

FINAL_ISO="${BUILD_DIR}/${ISO_NAME}"
mv "${ISO_PATH}" "${FINAL_ISO}"

echo ""
echo "=== Build successful! ==="
echo "ISO: ${FINAL_ISO}"
echo "Size: $(du -h "$FINAL_ISO" | cut -f1)"

echo ""
echo "Cleaning build chroot and binary directories to free space..."
cd "${BUILD_DIR}" && lb clean 2>/dev/null || true

echo "Post-build cleanup complete."

if [[ "${RUN_TEST:-0}" == "1" ]]; then
    echo ""
    echo "=== Running post-build verification ==="
    /magic_stick/scripts/verify.sh "${FINAL_ISO}"
    echo ""
    echo "=== Running boot test ==="
    /magic_stick/scripts/test-boot.sh "${FINAL_ISO}"
fi

echo ""
echo "Next steps:"
echo "  Verify ISO:  scripts/verify.sh"
echo "  Test boot:   scripts/test-boot.sh"
echo "  Flash to USB: docker run --rm --device=/dev/sdX -v \$(pwd):/magic_stick magic_stick:builder /magic_stick/scripts/flash.sh /dev/sdX"