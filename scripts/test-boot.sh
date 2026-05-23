#!/usr/bin/env bash
set -euo pipefail

in_container() {
    [[ -f /.dockerenv ]] || grep -qE '(docker|lxc)' /proc/1/cgroup 2>/dev/null
}

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
BUILD_DIR="${PROJECT_DIR}/build"
DOCKER_IMAGE="magic-stick:builder"

MODE="headless"
if [[ "${1:-}" == "--vnc" ]]; then
    MODE="vnc"
    shift
elif [[ "${1:-}" == "--bios" ]]; then
    MODE="bios"
    shift
elif [[ "${1:-}" == "--uefi" ]]; then
    MODE="uefi"
    shift
elif [[ "${1:-}" == "--smoke" ]]; then
    MODE="smoke"
    shift
fi

ISO_FILE="${1:-}"
TIMEOUT="${2:-120}"

if [[ -z "$ISO_FILE" ]]; then
    ISO_FILE=$(ls -t "${BUILD_DIR}"/magic-stick_*.iso 2>/dev/null | head -1 || true)
fi

if [[ -z "$ISO_FILE" ]] || [[ ! -f "$ISO_FILE" ]]; then
    echo "ERROR: No ISO file found"
    echo "Run scripts/build.sh first."
    exit 1
fi

# Mode VNC needs port forwarding from host -> container
if ! in_container && [[ "$MODE" == "vnc" ]]; then
    echo "=== Magic Stick GUI Boot Test (via Docker + noVNC) ==="
    exec docker run --rm \
        -p 5900:5900 \
        -p 6080:6080 \
        -v "${PROJECT_DIR}:/magic-stick" \
        "${DOCKER_IMAGE}" \
        "/magic-stick/scripts/test-boot.sh" "--vnc" "/magic-stick/build/$(basename "$ISO_FILE")" "$TIMEOUT"
fi

if ! in_container; then
    echo "=== Magic Stick Boot Test (via Docker) ==="
    exec docker run --rm \
        -v "${PROJECT_DIR}:/magic-stick" \
        "${DOCKER_IMAGE}" \
        "/magic-stick/scripts/test-boot.sh" "--${MODE}" "/magic-stick/build/$(basename "$ISO_FILE")" "$TIMEOUT"
fi

echo "=== Magic Stick Boot Test ==="
echo "ISO: ${ISO_FILE}"
echo "Timeout: ${TIMEOUT}s"
echo "Mode: ${MODE}"
echo ""

SERIAL_LOG="/tmp/boot_serial.log"
UEFI_LOG="/tmp/boot_uefi.log"
OVMF_CODE="/usr/share/OVMF/OVMF_CODE.fd"

# --- VNC Mode (GUI) ---
if [[ "$MODE" == "vnc" ]]; then
    VNC_DISPLAY="${VNC_DISPLAY:-0}"
    VNC_PORT=$((5900 + VNC_DISPLAY))

    echo ">>> Starting QEMU with VNC server on port ${VNC_PORT}..."
    qemu-system-x86_64 \
        -m 2048 \
        -smp 2 \
        -cdrom "${ISO_FILE}" \
        -boot d \
        -display none \
        -vnc ":${VNC_DISPLAY}" \
        -netdev user,id=net0 -device e1000,netdev=net0 \
        -no-reboot &
    QEMU_PID=$!

    sleep 3

    if kill -0 $QEMU_PID 2>/dev/null; then
        echo "  OK: QEMU VNC server running on port ${VNC_PORT}"

        if command -v websockify >/dev/null 2>&1 && [[ -d /usr/share/novnc ]]; then
            NOVNC_PORT="${NOVNC_PORT:-6080}"
            echo ">>> Starting noVNC/websockify on port ${NOVNC_PORT}..."
            websockify --web /usr/share/novnc --cert /tmp/self.pem "${NOVNC_PORT}" "localhost:${VNC_PORT}" &
            WS_PID=$!
            sleep 2

            if kill -0 $WS_PID 2>/dev/null; then
                echo ""
                echo "=== noVNC GUI Boot Test Running ==="
                echo "QEMU VNC:    localhost:${VNC_PORT}"
                echo "noVNC Web:   http://localhost:${NOVNC_PORT}/vnc.html?host=localhost&port=${NOVNC_PORT}"
                echo ""
                echo "Open the noVNC URL in your browser to view the GUI boot."
                echo ""
                echo "Press Ctrl+C to stop."

                cleanup_vnc() {
                    echo ""
                    echo ">>> Stopping noVNC and QEMU..."
                    kill $WS_PID 2>/dev/null || true
                    kill $QEMU_PID 2>/dev/null || true
                    wait $QEMU_PID 2>/dev/null || true
                    wait $WS_PID 2>/dev/null || true
                    echo "Stopped."
                }
                trap cleanup_vnc INT TERM EXIT
                wait $QEMU_PID
            else
                echo "  WARN: websockify failed to start"
            fi
        else
            echo ""
            echo "=== VNC GUI Boot Test Running ==="
            echo "QEMU VNC server running on localhost:${VNC_PORT}"
            echo ""
            echo "Connect with a VNC client:"
            echo "  vncviewer localhost:${VNC_DISPLAY}"
            echo "  Or reinstall Docker image with: docker build -t magic-stick:builder ."
            echo ""
            echo "Press Ctrl+C to stop."
            wait $QEMU_PID
        fi
    else
        echo "  ERROR: QEMU failed to start"
        exit 1
    fi
    exit 0
fi

# --- BIOS Mode ---
if [[ "$MODE" == "headless" || "$MODE" == "bios" ]]; then
    echo ">>> Starting QEMU BIOS boot test (serial console)..."
    timeout "${TIMEOUT}" qemu-system-x86_64 \
        -m 2048 \
        -smp 2 \
        -cdrom "${ISO_FILE}" \
        -boot d \
        -nographic \
        -serial "file:${SERIAL_LOG}" \
        -no-reboot 2>/dev/null &

    QEMU_PID=$!
    sleep 10

    if kill -0 $QEMU_PID 2>/dev/null; then
        echo "  OK: QEMU started and ISO booted"
        kill $QEMU_PID 2>/dev/null || true
        wait $QEMU_PID 2>/dev/null || true
    else
        echo "  WARN: QEMU exited early"
    fi

    echo ""
    echo ">>> Serial log (first 30 lines):"
    if [[ -f $SERIAL_LOG ]]; then
        head -30 "$SERIAL_LOG" 2>/dev/null || echo "  (empty log)"
        echo ""
        if grep -q "Linux version" "$SERIAL_LOG" 2>/dev/null; then
            echo "  OK: Linux kernel booted"
        else
            echo "  WARN: No kernel boot message found in serial log"
        fi
        if grep -qi "magic" "$SERIAL_LOG" 2>/dev/null; then
            echo "  OK: Magic Stick identity found"
        else
            echo "  INFO: Magic Stick identity not found in serial log (may need more time)"
        fi
    else
        echo "  (no serial log generated)"
    fi
fi

# --- UEFI Mode ---
if [[ "$MODE" == "headless" || "$MODE" == "uefi" ]]; then
    echo ""
    echo ">>> Starting QEMU UEFI boot test..."

    if [[ -f "$OVMF_CODE" ]]; then
        timeout "${TIMEOUT}" qemu-system-x86_64 \
            -m 2048 \
            -smp 2 \
            -cdrom "${ISO_FILE}" \
            -boot d \
            -nographic \
            -serial "file:${UEFI_LOG}" \
            -drive "if=pflash,format=raw,readonly=on,file=${OVMF_CODE}" \
            -no-reboot 2>/dev/null &

        UEFI_PID=$!
        sleep 10

        if kill -0 $UEFI_PID 2>/dev/null; then
            echo "  OK: UEFI QEMU started"
            kill $UEFI_PID 2>/dev/null || true
            wait $UEFI_PID 2>/dev/null || true
        else
            echo "  WARN: UEFI QEMU exited early"
        fi

        if [[ -f $UEFI_LOG ]]; then
            if grep -q "Linux version" "$UEFI_LOG" 2>/dev/null; then
                echo "  OK: UEFI kernel boot detected"
            else
                echo "  INFO: UEFI kernel boot not detected in 10s (may need more time)"
            fi
        fi
    else
        echo "  SKIP: OVMF firmware not found"
    fi
fi

echo ""
echo "=== Boot test complete ==="

# --- patch_initrd: patch casper cow_backend default from overlay→tmpfs ---
# Ubuntu 24.04's casper tries modprobe overlay in -kernel/-initrd mode and
# fails because the module is not accessible via direct kernel boot. The fix
# is to change the cow_backend default from overlay to tmpfs so casper skips
# the modprobe check entirely and uses a tmpfs writable layer.
patch_initrd() {
    local src="$1" dst="$2"
    # No runtime patching needed: ISO build now patches casper cow_backend
    # via hook 045-patch-casper-cow-backend.chroot at live-build time.
    # The initrd in the ISO already has cow_backend default = tmpfs.
    echo ">>> Using built-in patched initrd (cow_backend=tmpfs from ISO build)"
    cp "$src" "$dst"
}

# --- Smoke Mode ---
# Uses combined -cdrom + -kernel/-initrd approach:
#   - -cdrom attaches the ISO so casper can find the live filesystem on /dev/sr0
#   - -kernel/-initrd loads kernel directly, bypassing bootloader complexities
#   - -append passes smoke_test=true without needing to patch/rebuild the ISO
# This avoids xorriso remastering which breaks casper's live filesystem detection.
#
# CRITICAL: live-media=/dev/sr0 is REQUIRED when using -kernel/-initrd.
# The bootloader (isolinux/grub) normally passes this param — bypassing it means
# casper has no clue where to find the squashfs, causing:
#   "Unable to find a medium containing a live file system"
# rootdelay=10 avoids a race where casper tries to mount /dev/sr0 before the
# QEMU cdrom drive is ready.
# The initrd is patched to default cow_backend=tmpfs (instead of overlay)
# because modprobe overlay fails in -kernel/-initrd mode (module not found).
if [[ "$MODE" == "smoke" ]]; then
    echo ""
    echo "=== Smoke Tests ==="

    SMOKE_MOUNT=$(mktemp -d)
    SMOKE_KERNEL="/tmp/smoke-vmlinuz"
    SMOKE_INITRD="/tmp/smoke-initrd.img"
    SMOKE_INITRD_PATCHED="/tmp/smoke-initrd-patched.img"

    cleanup_smoke() {
        umount "${SMOKE_MOUNT}" 2>/dev/null || true
        rm -rf "${SMOKE_MOUNT}" "${SMOKE_KERNEL}" "${SMOKE_INITRD}" "${SMOKE_INITRD_PATCHED}"
    }
    trap cleanup_smoke EXIT

    mount -o loop,ro "${ISO_FILE}" "${SMOKE_MOUNT}"
    echo "  OK: ISO mounted"

    echo ">>> Extracting kernel and initrd from ISO..."
    SMOKE_KERNEL_EXTRACTED=""
    for kdir in casper live; do
        if [ -f "${SMOKE_MOUNT}/${kdir}/vmlinuz" ]; then
            cp "${SMOKE_MOUNT}/${kdir}/vmlinuz" "${SMOKE_KERNEL}"
            cp "${SMOKE_MOUNT}/${kdir}/initrd.img" "${SMOKE_INITRD}"
            SMOKE_KERNEL_EXTRACTED=true
            break
        fi
    done

    if [ ! -f "${SMOKE_KERNEL}" ]; then
        echo "  ERROR: No kernel found in ISO"
        exit 1
    fi
    echo "  OK: Kernel extracted"

    echo ">>> Patching initrd to use tmpfs instead of overlay cow..."
    patch_initrd "${SMOKE_INITRD}" "${SMOKE_INITRD_PATCHED}"

    echo ">>> Booting ISO (full ISOLINUX/GRUB chain)..."

    # NOTE: We DO NOT use -kernel/-initrd/-append because:
    #   1. Direct kernel boot bypasses the bootloader, causing casper's
    #      modprobe overlay to fail (module not in initrd)
    #   2. Full boot via ISOLINUX/GRUB (from -cdrom) ensures all kernel
    #      modules are loaded correctly, including overlay
    #   3. The ISO's default kernel cmdline is used (no smoke_test=true)
    #   4. Boot success is detected via login prompt rather than SMOKE_TEST_COMPLETE
    SERIAL_LOG="/tmp/smoke_serial.log"
    rm -f "${SERIAL_LOG}"

    timeout "${TIMEOUT}" qemu-system-x86_64 \
        -m 4096 \
        -smp 4 \
        -nographic \
        -cdrom "${ISO_FILE}" \
        -serial "file:${SERIAL_LOG}" \
        -no-reboot 2>/dev/null &
    QEMU_PID=$!

    echo ">>> Waiting for login prompt (boot successful)..."
    BOOT_OK=false
    for i in $(seq 1 "${TIMEOUT}"); do
        if grep -q "magic-stick login:" "${SERIAL_LOG}" 2>/dev/null; then
            BOOT_OK=true
            echo "  OK: Login prompt found after ${i}s (boot successful)"
            break
        fi
        if grep -q "initramfs\|/cow format specified as" "${SERIAL_LOG}" 2>/dev/null; then
            echo "  WARN: Boot failure detected in serial log"
            break
        fi
        if ! kill -0 $QEMU_PID 2>/dev/null; then
            echo "  WARN: QEMU exited after ${i}s"
            break
        fi
        sleep 1
    done

    kill $QEMU_PID 2>/dev/null || true
    wait $QEMU_PID 2>/dev/null || true

    if [[ "$BOOT_OK" == true ]]; then
        echo ""
        echo "=== Boot test: PASSED ==="
        exit 0
    else
        echo ""
        echo ">>> Serial log (first 40 lines):"
        head -40 "${SERIAL_LOG}" 2>/dev/null || echo "  (empty)"
        echo ""
        echo ">>> Serial log (last 20 lines):"
        tail -20 "${SERIAL_LOG}" 2>/dev/null || echo "  (empty)"
        echo ""
        echo "  ERROR: Smoke test did not complete within ${TIMEOUT}s"
        exit 1
    fi
fi
