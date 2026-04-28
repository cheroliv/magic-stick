# Magic Stick — Your entire dev environment, in your pocket

**https://github.com/cheroliv/magic_stick**

Ever wasted 30 minutes setting up a new machine just to get to work? **Magic Stick** solves that for good.

A bootable Xubuntu 24.04 USB drive that gives you the **exact same environment on any PC** — no install, no config, no friction. Plug it in, boot, and you're ready.

## What makes it special

### Atomic A/B updates with instant rollback
Two system partitions (A + B). Updates write to the *inactive* one, then flip the boot flag. New version broken? Reboot into the old one — zero downtime. Your **persistent data survives every update**, untouched.

### Full dev toolkit, pre-installed

- **Container** — Docker CE, Podman
- **Local AI** — **Ollama** (run LLMs directly on-device)
- **JVM** — SDKMAN + JDK 25 Temurin
- **Node.js** — NVM, pnpm
- **Python** — Python 3.14.4 + uv
- **Search** — ripgrep, fd, fzf
- **Git** — lazygit
- **Network** — nmap, iperf3, Wireshark
- **HTTP** — xh, httpie
- **Shell** — zsh + starship
- **Editors** — VS Code, JetBrains Toolbox
- **CLI** — GitHub CLI (gh)

### Use cases
- **Trainers**: hand every student the same drive, day-one ready
- **Field techs**: full FTTH/network diagnostics on any hardware
- **Nomadic devs**: find your entire stack wherever you go
- **Teams**: shared standardized environment, zero setup waste

## Try it
Download the ISO from **SourceForge** ([link on GitHub](https://sourceforge.net/projects/magic-stick/files/)), flash to USB with `dd`, and boot.

Full docs: **http://cheroliv.com/magic_stick/**

Dont be too hard on me, still in dev

## Docker image
Don't have a USB drive handy? Pull `cheroliv/magic-stick-cli` from Docker Hub — the entire CLI stack (Ollama + JDK 25 + Python 3.14 + Node.js + ripgrep + fzf...) ready instantly:

`docker run --rm -it cheroliv/magic-stick-cli`

Built in CI/CD with GitHub Actions + live-build + Docker. Apache 2.0.
