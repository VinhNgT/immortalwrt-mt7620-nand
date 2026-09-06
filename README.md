# ImmortalWrt for the Xiaomi Mi Router 3 (miwifi-r3)

> [!WARNING]
> This project is vibe coded with Anthropic Claude Fable 5 — use at your own risk.

Modern, maintained firmware for the Xiaomi Mi Router 3. Official
OpenWrt dropped this device years ago because mainline Linux lost the
driver for its NAND storage; this project keeps it alive on **current
ImmortalWrt** by maintaining that driver and the device support as a
short commit series on top of the ImmortalWrt release — with
everything a user expects: LuCI web UI, current kernel, installable
packages, and safe upgrades.

This repository is a fork of
[immortalwrt/immortalwrt](https://github.com/immortalwrt/immortalwrt).
Branch `25.12` is the ImmortalWrt `v25.12.1` tag plus the port; the
name refers to the `mt7620-nand` support it adds to the `ramips`
target.

## Status

Complete, verified on real hardware.

- Everything works: WiFi (2.4 + 5 GHz), switch, USB, web UI, storage,
  normal sysupgrade — on ImmortalWrt `v25.12.1` (kernel 6.12).
- Installing never touches the bootloader, and every failure state
  short of deliberately destroying the bootloader is recoverable.
- The NAND driver's silent error-handling defect was fixed along the
  way — flash bit-errors now heal themselves automatically.

## Hardware

| | |
|---|---|
| SoC | MediaTek MT7620A @ 580 MHz (MIPS 24KEc, mipsel) |
| RAM | 128 MiB DDR2 |
| Flash | 128 MiB parallel NAND, ESMT F59L1G81LA |
| WiFi | 2.4 GHz 802.11n (rt2800soc) + 5 GHz 802.11ac (MT7612E, mt76x2) |
| Ethernet | 3× 100M (2 LAN, 1 WAN) |
| USB | 1× USB 2.0 |
| Serial | 115200 8N1, 3.3 V TTL |

"R3" only — the 3G/3C/3A/3P are different devices and share nothing
here.

## Quick start

1. Download `…sysupgrade.bin` and `sha256sums` from the newest
   [GitHub release](../../releases) and verify the checksum.
2. If this is your first flash: **make a backup first** —
   [mt7620-nand/docs/RECOVERY.md](mt7620-nand/docs/RECOVERY.md).
3. Flash it from your current OpenWrt-family firmware's web UI
   (settings **not** kept when switching firmware families) — full
   steps in [mt7620-nand/docs/GUIDE.md](mt7620-nand/docs/GUIDE.md).
4. The router comes back at `192.168.1.1` (user `root`, no password —
   set one).

Adding packages later: ordinary packages install normally; kernel
modules come from the release's bundled ImageBuilder — the guide
covers both, plus the quirks worth knowing.

## Documentation

**For users:**

- [mt7620-nand/docs/GUIDE.md](mt7620-nand/docs/GUIDE.md) — installing, upgrading, adding
  packages, common use cases, quirks
- [mt7620-nand/docs/RECOVERY.md](mt7620-nand/docs/RECOVERY.md) — backup, serial console, and
  every path back from a bad flash

**For developers** (how it works and why):

- [mt7620-nand/docs/DEVELOPMENT.md](mt7620-nand/docs/DEVELOPMENT.md) — repo structure,
  building, testing, cutting releases, following upstream
- [mt7620-nand/docs/PORT-NOTES.md](mt7620-nand/docs/PORT-NOTES.md) — technical reference:
  the NAND driver, what the port changes, the fixes made here
- [mt7620-nand/docs/PROVENANCE.md](mt7620-nand/docs/PROVENANCE.md) — where the X-Wrt-derived
  files came from, by content hash
- [mt7620-nand/docs/RESEARCH-LOG.md](mt7620-nand/docs/RESEARCH-LOG.md) — how the conclusions
  were reached, dead ends included

The port was first developed in
[VinhNgT/immortalwrt-miwifi-r3](https://github.com/VinhNgT/immortalwrt-miwifi-r3)
as a patch series applied to upstream checkouts; that repository is
archived and this fork supersedes it.

## Credits & license

The NAND driver and original device support are by Chen Minqiang
([x-wrt](https://github.com/x-wrt/x-wrt)); this repo forward-ports
that work onto ImmortalWrt and adds fixes of its own. Licensed
GPL-2.0, like the OpenWrt code it derives from (see
[COPYING](COPYING) and [LICENSES/](LICENSES/)).
