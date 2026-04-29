#!/usr/bin/env python3
"""Patch lb_binary_iso pour xorriso + UEFI support."""
import sys
import os

SCRIPT = sys.argv[1] if len(sys.argv) > 1 else "/usr/lib/live/build/lb_binary_iso"

if not os.path.isfile(SCRIPT):
    print(f"SKIP: {SCRIPT} not found")
    sys.exit(0)

with open(SCRIPT, 'r', encoding='utf-8') as f:
    content = f.read()

# Replace genisoimage with xorriso -as mkisofs
content = content.replace(
    'Check_package chroot/usr/bin/genisoimage genisoimage',
    'Check_package chroot/usr/bin/xorriso xorriso'
)

# Replace the genisoimage command line in binary.sh generation
old_cmd_line = 'genisoimage ${GENISOIMAGE_OPTIONS} ${GENISOIMAGE_OPTIONS_EXTRA} -o ${IMAGE} binary'

new_cmd_line = '''if [ -d "binary/EFI/BOOT" ] && [ -f "binary/EFI/BOOT/BOOTX64.EFI" ]; then
    xorriso -as mkisofs -iso-level 3 ${GENISOIMAGE_OPTIONS} ${GENISOIMAGE_OPTIONS_EXTRA} \\
        --efi-boot EFI/BOOT/BOOTX64.EFI \\
        -isohybrid-mbr /usr/lib/ISOLINUX/isohdpfx.bin \\
        -o ${IMAGE} binary
else
    xorriso -as mkisofs -iso-level 3 ${GENISOIMAGE_OPTIONS} ${GENISOIMAGE_OPTIONS_EXTRA} -o ${IMAGE} binary
fi'''

content = content.replace(old_cmd_line, new_cmd_line)

content = content.replace('genisoimage generic options', 'xorriso (mkisofs mode) generic options')
content = content.replace('genisoimage live-build specific options', 'xorriso (mkisofs mode) live-build specific options')
content = content.replace('genisoimage architecture specific options', 'xorriso (mkisofs mode) architecture specific options')

with open(SCRIPT, 'w', encoding='utf-8') as f:
    f.write(content)

print(f"PATCHED: {SCRIPT}")
