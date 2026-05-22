#!/usr/bin/env bash
set -euo pipefail

# ==============================================================================
# flash.sh — Flash ISO magic-stick sur clé USB
# ==============================================================================

# Couleurs
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
BUILD_DIR="${PROJECT_DIR}/build"

usage() {
    echo "Flash the Magic Stick ISO to a USB drive."
    echo ""
    echo "Usage:"
    echo "  sudo $0                             # Mode interactif — auto-découverte ISO + listing devices"
    echo "  sudo $0 <device>                    # Mode device direct (ex: /dev/sdc)"
    echo "  sudo $0 <device> <iso_path>         # Device + ISO explicite"
    echo ""
    echo "  $0 --help                           # Ce message"
    echo ""
    echo "WARNING: This will ERASE ALL DATA on the target device!"
    echo ""
    echo "Run inside Docker (no sudo needed on host):"
    echo "  docker run --rm --device=/dev/sdX -v \$(pwd):/magic-stick magic-stick:builder scripts/flash.sh /dev/sdX"
    echo ""
    echo "First, identify your USB drive with:"
    echo "  lsblk"
}

# ── Détection du mode (argument device donné ou pas) ─────────────────────────

if [[ "${1:-}" == "--help" || "${1:-}" == "-h" ]]; then
    usage
    exit 0
fi

# ── Résoudre l'ISO ───────────────────────────────────────────────────────────

DEFAULT_ISO=$(ls -t "${BUILD_DIR}"/magic-stick_*.iso 2>/dev/null | head -1)

if [[ $# -ge 2 ]]; then
    # ISO explicite passée en 2ème argument
    ISO_FILE="$2"
elif [[ -n "$DEFAULT_ISO" ]]; then
    ISO_FILE="$DEFAULT_ISO"
else
    echo -e "${RED}ERROR: No ISO file found in ${BUILD_DIR}/${NC}"
    echo -e "${YELLOW}Run scripts/build.sh first.${NC}"
    exit 1
fi

if [[ ! -f "$ISO_FILE" ]]; then
    echo -e "${RED}ERROR: ISO not found → ${ISO_FILE}${NC}"
    exit 1
fi

ISO_SIZE=$(stat -c%s "$ISO_FILE" 2>/dev/null || stat -f%z "$ISO_FILE" 2>/dev/null)
ISO_SIZE_HUMAN=$(numfmt --to=iec "$ISO_SIZE" 2>/dev/null || echo "${ISO_SIZE} octets")

# ── Résoudre le device ───────────────────────────────────────────────────────

if [[ $# -ge 1 && "${1:0:1}" == "/" ]]; then
    # Mode non-interactif : device donné en argument
    DEVICE="$1"
    MODE="direct"
else
    # Mode interactif : pas de device, on liste et demande
    MODE="interactive"
fi

# ── Banner ───────────────────────────────────────────────────────────────────

echo -e "${CYAN}=== Magic Stick Flasher ===${NC}"
echo ""
echo -e "ISO   : ${GREEN}${ISO_FILE}${NC}"
echo -e "Taille: ${YELLOW}${ISO_SIZE_HUMAN}${NC}"
echo ""

# ── sudo upfront ─────────────────────────────────────────────────────────────

if [[ "$(id -u)" -ne 0 ]]; then
    echo -e "${YELLOW}🔑 Le flashage nécessite les droits root.${NC}"
    echo -e "${YELLOW}   Saisis le mot de passe sudo ci-dessous :${NC}"
    sudo -v
    echo -e "${GREEN}✅ Privilèges sudo acquis.${NC}"
    echo ""

    # Prolonger le timeout sudo pendant toute la durée du script
    while true; do sudo -n true; sleep 30; done 2>/dev/null &
    SUDO_KEEPER_PID=$!
    trap 'kill $SUDO_KEEPER_PID 2>/dev/null; wait $SUDO_KEEPER_PID 2>/dev/null' EXIT

    # Wrapper : exécute en sudo si pas déjà root
    run_priv() { sudo "$@"; }
else
    run_priv() { "$@"; }
fi

# ── Mode interactif : lister les devices ─────────────────────────────────────

if [[ "$MODE" == "interactive" ]]; then
    echo -e "${YELLOW}Disques disponibles :${NC}"
    echo -e "${CYAN}────────────────────────────────────────────${NC}"
    lsblk -o NAME,SIZE,MODEL,MOUNTPOINT,TYPE | grep -E 'disk|part'
    echo -e "${CYAN}────────────────────────────────────────────${NC}"
    echo ""
    echo -e "${YELLOW}⚠️  Repère bien ta clé USB (taille, modèle).${NC}"
    echo -e "${YELLOW}   Une erreur peut EFFACER ton disque système.${NC}"
    echo ""
    read -rp "Périphérique cible (ex: sdc, sdd, nvme0n1) : " DEV_NAME

    DEVICE="/dev/${DEV_NAME}"
fi

# ── Vérifications du device ──────────────────────────────────────────────────

if [[ ! -b "$DEVICE" ]]; then
    echo -e "${RED}ERROR: ${DEVICE} is not a block device${NC}"
    exit 1
fi

# Anti-écrasement du disque système
ROOT_DISK=$(lsblk -no PKNAME "$(findmnt -n -o SOURCE /)" 2>/dev/null || \
            lsblk -ndo NAME "$(df / | tail -1 | awk '{print $1}')" 2>/dev/null || \
            echo "")
DEV_BASENAME=$(basename "$DEVICE")

if [[ -n "$ROOT_DISK" && "$DEV_BASENAME" == "$ROOT_DISK" ]]; then
    echo -e "${RED}!!! CRITICAL ERROR: ${DEVICE} is the system disk !!!${NC}"
    exit 1
fi

# Double-check : le device ne contient pas la racine
MOUNTED_ROOT=$(findmnt -n -o SOURCE / 2>/dev/null | sed 's/[0-9]*$//' || true)
if [[ -n "$MOUNTED_ROOT" && "$DEVICE" == "$MOUNTED_ROOT" ]]; then
    echo -e "${RED}!!! CRITICAL ERROR: ${DEVICE} contains the root filesystem !!!${NC}"
    exit 1
fi

# ── Vérifications de taille ──────────────────────────────────────────────────

DEVICE_SIZE=$(blockdev --getsize64 "$DEVICE" 2>/dev/null || echo 0)
MIN_DEVICE_SIZE=$((8 * 1024 * 1024 * 1024))  # 8 GiB (taille ISO Xubuntu ~4Go + marge)

if [[ "$DEVICE_SIZE" -gt 0 ]]; then
    DEV_SIZE_HUMAN=$(numfmt --to=iec "$DEVICE_SIZE" 2>/dev/null || echo "${DEVICE_SIZE}")

    if [[ "$DEVICE_SIZE" -lt "$MIN_DEVICE_SIZE" ]]; then
        echo -e "${RED}ERROR: Device ${DEVICE} (${DEV_SIZE_HUMAN}) is too small${NC}"
        echo -e "${RED}Minimum required: 8 GB${NC}"
        exit 1
    fi

    if [[ "$ISO_SIZE" -ge "$DEVICE_SIZE" ]]; then
        echo -e "${RED}ERROR: ISO (${ISO_SIZE_HUMAN}) is larger than device (${DEV_SIZE_HUMAN})${NC}"
        exit 1
    fi

    echo -e "Device: ${CYAN}${DEVICE}${NC} (${YELLOW}${DEV_SIZE_HUMAN}${NC})"
else
    echo -e "Device: ${CYAN}${DEVICE}${NC}"
fi

echo ""

# ── Confirmation ─────────────────────────────────────────────────────────────

echo -e "${RED}╔══════════════════════════════════════════════════════╗${NC}"
echo -e "${RED}║   WARNING: ALL DATA ON ${DEVICE} WILL BE ERASED !    ║${NC}"
echo -e "${RED}╚══════════════════════════════════════════════════════╝${NC}"
echo ""
echo -e "ISO  : ${GREEN}${ISO_FILE}${NC}"
echo -e "CIBLE: ${RED}${DEVICE}${NC}"
echo ""
read -rp "Type 'YES' to confirm: " CONFIRM

if [[ "$CONFIRM" != "YES" ]]; then
    echo -e "${YELLOW}Aborted. No data was touched.${NC}"
    exit 0
fi

# ── Flash ! ──────────────────────────────────────────────────────────────────

echo ""
echo -e "${YELLOW}Unmounting partitions on ${DEVICE}...${NC}"
lsblk -n -o NAME,MOUNTPOINT "$DEVICE" 2>/dev/null | while read -r name mp; do
    if [[ -n "$mp" ]]; then
        echo "  Unmounting ${mp}..."
        run_priv umount "/dev/${name}" 2>/dev/null || true
    fi
done
run_priv umount "${DEVICE}"* 2>/dev/null || true

echo ""
echo -e "${YELLOW}Flashing ISO to ${DEVICE}...${NC}"
echo -e "${CYAN}  dd bs=4M if=${ISO_FILE} of=${DEVICE} conv=fsync${NC}"
echo ""
run_priv dd if="$ISO_FILE" of="$DEVICE" bs=4M status=progress conv=fsync

echo ""
echo -e "${YELLOW}Syncing...${NC}"
run_priv sync

echo ""
echo -e "${GREEN}══════════════════════════════════════════════════${NC}"
echo -e "${GREEN}  ✓ Flash complete!${NC}"
echo -e "${GREEN}  You can now boot from the USB drive.${NC}"
echo -e "${GREEN}══════════════════════════════════════════════════${NC}"
echo ""
echo "Next steps for A/B partitioning:"
echo "  sudo ${SCRIPT_DIR}/update-system.sh --setup-ab ${DEVICE}"
echo ""
echo "  Pour un test boot rapide sans reboot physique :"
echo "    cd ${PROJECT_DIR}"
echo "    sudo ./scripts/test-boot.sh"
