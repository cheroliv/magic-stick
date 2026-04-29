#!/usr/bin/env python3
"""Patch lb_binary_syslinux pour casper et Ubuntu 24.04 compatibility."""
import sys
import os

SCRIPT = sys.argv[1] if len(sys.argv) > 1 else "/usr/lib/live/build/lb_binary_syslinux"

if not os.path.isfile(SCRIPT):
    print(f"SKIP: {SCRIPT} not found")
    sys.exit(0)

with open(SCRIPT, 'r', encoding='utf-8') as f:
    c = f.read()

# Casper paths
c = c.replace('binary/live/vmlinuz', 'binary/casper/vmlinuz')
c = c.replace('binary/live/initrd.img', 'binary/casper/initrd.img')
c = c.replace('/live/vmlinuz', '/casper/vmlinuz')
c = c.replace('/live/initrd.img', '/casper/initrd.img')

# rsvg → rsvg-convert for Ubuntu 24.04
c = c.replace(
    'rsvg --format png --height 480 --width 640 splash.svg splash.png',
    'rsvg-convert --format png --height 480 --width 640 -o splash.png splash.svg'
)
c = c.replace(
    'rsvg --format png --height 480 --width 640 "${_TARGET}/splash.svg" "${_TARGET}/splash.png"',
    'rsvg-convert --format png --height 480 --width 640 -o "${_TARGET}/splash.png" "${_TARGET}/splash.svg"'
)
c = c.replace(
    'Check_package chroot/usr/bin/rsvg librsvg2-bin',
    'Check_package chroot/usr/bin/rsvg-convert librsvg2-bin'
)

with open(SCRIPT, 'w', encoding='utf-8') as f:
    f.write(c)

print(f"PATCHED: {SCRIPT}")
