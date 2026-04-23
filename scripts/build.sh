#!/usr/bin/env bash
set -euo pipefail

MAGIC_STICK_VERSION="0.1.0"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
BUILD_DIR="${PROJECT_DIR}/build"
CONFIG_DIR="${PROJECT_DIR}/config/live-build"
ISO_NAME="magic_stick_${MAGIC_STICK_VERSION}.iso"

echo "=== Magic Stick Builder v${MAGIC_STICK_VERSION} ==="
echo "Project dir: ${PROJECT_DIR}"
echo "Build dir:    ${BUILD_DIR}"
echo "ISO name:     ${ISO_NAME}"
echo ""

usage() {
    echo "Usage: $0 [OPTIONS]"
    echo ""
    echo "Options:"
    echo "  -c, --clean     Clean build directory before building"
    echo "  -h, --help      Show this help message"
    echo "  -v, --verbose   Verbose output"
    echo ""
    echo "This script builds a Xubuntu-based live ISO using live-build."
    echo "The resulting ISO can be flashed to a USB drive."
    echo ""
    echo "Prerequisites:"
    echo "  - live-build package installed"
    echo "  - xorriso"
    echo "  - syslinux or grub-efi"
    echo "  - squashfs-tools"
}

CLEAN=false
VERBOSE=false

while [[ $# -gt 0 ]]; do
    case $1 in
        -c|--clean)
            CLEAN=true
            shift
            ;;
        -v|--verbose)
            VERBOSE=true
            shift
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            echo "Unknown option: $1"
            usage
            exit 1
            ;;
    esac
done

check_prerequisites() {
    echo "Checking prerequisites..."
    local missing=()
    
    for cmd in lb live-build xorriso mksquashfs; do
        if ! command -v "$cmd" &>/dev/null; then
            missing+=("$cmd")
        fi
    done
    
    if [[ ${#missing[@]} -gt 0 ]]; then
        echo "ERROR: Missing prerequisites: ${missing[*]}"
        echo "Install with: sudo apt install live-build xorriso squashfs-tools"
        exit 1
    fi
    
    echo "All prerequisites met."
}

setup_build_dir() {
    mkdir -p "${BUILD_DIR}"
    
    if [[ "$CLEAN" == true ]]; then
        echo "Cleaning build directory..."
        lb clean
    fi
    
    if [[ ! -f "${BUILD_DIR}/config/base" ]]; then
        echo "Initializing live-build configuration..."
        cd "${BUILD_DIR}"
        lb config
    fi
}

apply_config() {
    echo "Applying Magic Stick configuration..."
    
    if [[ -d "${CONFIG_DIR}/package-lists" ]]; then
        cp -r "${CONFIG_DIR}/package-lists/"* "${BUILD_DIR}/config/package-lists/"
    fi
    
    if [[ -d "${CONFIG_DIR}/hooks" ]]; then
        cp -r "${CONFIG_DIR}/hooks/"* "${BUILD_DIR}/config/hooks/"
    fi
    
    if [[ -d "${CONFIG_DIR}/includes.chroot" ]]; then
        cp -r "${CONFIG_DIR}/includes.chroot/"* "${BUILD_DIR}/config/includes.chroot/"
    fi
    
    if [[ -d "${CONFIG_DIR}/includes.binary" ]]; then
        cp -r "${CONFIG_DIR}/includes.binary/"* "${BUILD_DIR}/config/includes.binary/"
    fi
}

build_iso() {
    echo "Building ISO... (this will take 30-60 minutes)"
    cd "${BUILD_DIR}"
    lb build
    
    local iso_path="${BUILD_DIR}/live-image-*.iso"
    if ls $iso_path &>/dev/null; then
        local final_iso="${BUILD_DIR}/${ISO_NAME}"
        mv $iso_path "$final_iso"
        echo ""
        echo "=== Build successful! ==="
        echo "ISO: ${final_iso}"
        echo "Size: $(du -h "$final_iso" | cut -f1)"
        echo ""
        echo "Flash to USB with:"
        echo "  sudo ${SCRIPT_DIR}/flash.sh /dev/sdX"
    else
        echo "ERROR: Build failed - no ISO file generated"
        exit 1
    fi
}

check_prerequisites
setup_build_dir
apply_config
build_iso

echo "Done."