# ImmortalWrt for `ramips/mt7620_nand` (Xiaomi Mi Router 3)

> [!WARNING]
> This project is vibe coded with Anthropic Claude Fable 5 — use at your own risk.

Modern, maintained ImmortalWrt builds for MediaTek MT7620 devices with
parallel NAND flash on the SoC's own controller — starting with the
**Xiaomi Mi Router 3 (`xiaomi_miwifi-r3`)** and structured as a clean
`mt7620_nand` subtarget so additional MT7620 NAND boards can be added
easily later.

Official OpenWrt dropped the Mi Router 3 in 2017, when the kernel bump
to 4.9 lost the driver for its NAND storage; this project keeps it alive
on a **current ImmortalWrt release** by maintaining that driver and the
device support as a short commit series on top of the release, and
distributes a **standalone ImageBuilder** bundling the kernel and every
kernel module (`CONFIG_ALL_NONSHARED=y`) while pulling userland packages
(like LuCI) from the official ImmortalWrt feeds.

This repository is a fork of
[immortalwrt/immortalwrt](https://github.com/immortalwrt/immortalwrt).
Branch `25.12` is the ImmortalWrt `v25.12.2` tag plus the port; the
name refers to the `mt7620_nand` subtarget it adds to the `ramips`
target.

## Status

Complete, verified on real hardware (a Mi Router 3 unit, August
2026, ImmortalWrt `v25.12.1` with kernel 6.12) and rebased onto
`v25.12.2`.

- Everything works: WiFi (2.4 + 5 GHz), switch, USB, web UI, storage,
  normal sysupgrade.
- Installing never touches the bootloader, and every failure state
  short of deliberately destroying the bootloader is recoverable.
- The NAND driver as inherited silently swallowed corrected flash
  bit-errors, so they were never healed; this project fixes that, and
  the firmware repairs such errors automatically.

The pinned ImmortalWrt version is the branch you are looking at:
branch `25.12` is the upstream tag `v25.12.2` plus this project's
commits. Each GitHub release names the exact upstream commit it was
built from.

## Supported hardware

| Device | Profile | SoC / Flash | Status |
|---|---|---|---|
| Xiaomi Mi Router R3 | `xiaomi_miwifi-r3` | MT7620A @ 580 MHz, 128 MiB DDR2, 128 MiB ESMT F59L1G81LA parallel NAND, 2.4 GHz (`rt2800soc`) + 5 GHz (`mt76x2`), 3× 100M Ethernet, 1× USB 2.0 | Hardware-verified (`v25.12.1`) |

"R3" only — the 3G/3C/3A/3P are different devices and share nothing
here.

## Quick start

Releases ship a **standalone ImageBuilder** rather than pre-built
device `.bin` files so you can bake LuCI, VPNs, USB storage, or any
custom package list directly into your image in ~1 minute on x86_64
Linux (or WSL / Docker on Windows):

1. Download `immortalwrt-imagebuilder-….tar.zst` and `sha256sums` from
   the newest [GitHub release](../../releases) and verify the checksum
   (`sha256sum -c --ignore-missing sha256sums`).
2. Unpack and build your device images (for Mi Router 3 with LuCI):

   ```bash
   tar xf immortalwrt-imagebuilder-*.tar.zst && cd immortalwrt-imagebuilder-*/
   make image PROFILE=xiaomi_miwifi-r3 PACKAGES="luci"
   ```

   Images (`…sysupgrade.bin`, `…initramfs-kernel.bin`, recovery
   images, `.manifest`, and `sha256sums`) appear in
   `bin/targets/ramips/mt7620_nand/`.
3. If this is your first flash: **make a backup first** —
   [mt7620-nand/docs/RECOVERY.md](mt7620-nand/docs/RECOVERY.md).
4. Flash `…sysupgrade.bin` from your current OpenWrt-family firmware's
   web UI (settings **not** kept when switching firmware families) —
   full steps in [mt7620-nand/docs/GUIDE.md](mt7620-nand/docs/GUIDE.md).
5. The router comes back at `192.168.1.1` (user `root`, no password —
   set one).

Adding packages later: ordinary userland packages install normally
from official feeds; kernel modules come from the release's
ImageBuilder — the guide covers both, plus the quirks worth knowing.

## Documentation

**For users:**

- [mt7620-nand/docs/GUIDE.md](mt7620-nand/docs/GUIDE.md) — generating
  images from the ImageBuilder, installing, upgrading, adding packages,
  common use cases, quirks
- [mt7620-nand/docs/RECOVERY.md](mt7620-nand/docs/RECOVERY.md) —
  backup, serial console, and every path back from a bad flash

**For developers** (how it works and why):

- [mt7620-nand/docs/DEVELOPMENT.md](mt7620-nand/docs/DEVELOPMENT.md) —
  repo structure, building, testing, cutting releases, following
  upstream
- [mt7620-nand/docs/PORT-NOTES.md](mt7620-nand/docs/PORT-NOTES.md) —
  technical reference: the NAND driver, what the port changes, the fixes
  made here
- [mt7620-nand/docs/PROVENANCE.md](mt7620-nand/docs/PROVENANCE.md) —
  where the X-Wrt-derived files came from, by content hash
- [mt7620-nand/docs/RESEARCH-LOG.md](mt7620-nand/docs/RESEARCH-LOG.md)
  — how the conclusions were reached, dead ends included

History: from August to September 2026 the port lived in
[VinhNgT/immortalwrt-miwifi-r3](https://github.com/VinhNgT/immortalwrt-miwifi-r3)
as a patch series applied to upstream checkouts. That repository is
archived; this fork replaced it on 2026-09-06 and its release
`v25.12.1-r1` is the same firmware as that repository's `v25.12.1-r1`.

## Credits & license

The NAND driver and original device support are by Chen Minqiang
([x-wrt](https://github.com/x-wrt/x-wrt)); this repo forward-ports
that work onto ImmortalWrt and adds fixes of its own. Licensed
GPL-2.0, like the OpenWrt code it derives from (see
[COPYING](COPYING) and [LICENSES/](LICENSES/)).
