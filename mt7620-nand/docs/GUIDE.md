# User guide

Running ImmortalWrt on the Xiaomi Mi Router 3: getting firmware,
installing, upgrading, adding packages, and the quirks worth knowing.
Before your first ever flash — and whenever something goes wrong —
read [RECOVERY.md](RECOVERY.md).

## Getting firmware

Firmware comes from this repo's **GitHub releases**. Releases are
tagged `<immortalwrt-version>-rN` (for example `v25.12.1-r2`): the
ImmortalWrt version plus a port build number. When several releases
exist for the same ImmortalWrt version, take the newest `-rN` unless
its notes say otherwise.

Each release contains:

| asset | purpose |
|---|---|
| `…sysupgrade.bin` | normal install/upgrade image — this is the one you flash |
| `…initramfs-kernel.bin` | test/recovery system that runs entirely from RAM, writes nothing (see [RECOVERY.md](RECOVERY.md)) |
| `…factory.bin`, `…breed-factory.bin` | only for pb-boot/breed web-recovery uploads — not used with the stock bootloader |
| `…kernel1.bin`, `…rootfs0.bin` | split images for manual partition writes during recovery |
| `…imagebuilder….tar.zst` | builds custom images / provides kernel modules for **this release** (below) |
| `sha256sums` | checksums — verify your download |
| `….manifest` | full list of packages inside the image |

## Installing

### Coming from X-Wrt or another OpenWrt-family firmware

1. Make a full NAND backup first if you don't have one —
   [RECOVERY.md](RECOVERY.md#the-backup--make-one-before-anything-else).
2. In the running firmware's web UI (X-Wrt LuCI lives at
   `192.168.15.1` by default): System → Backup / Flash Firmware →
   flash the `…sysupgrade.bin`.
3. **Uncheck "Keep settings"** — configuration must not carry over
   between firmware families.
4. Verify the checksum the UI displays against the release's
   `sha256sums`, proceed, and leave the device alone for 3–5 minutes.
   Flashing over WiFi works (the image is fully uploaded before any
   writing starts), though a LAN cable lets you watch the router come
   back. **Never power off mid-write.**
5. The router comes back at **`192.168.1.1`**, user `root`, **no
   password** — set one immediately. WiFi broadcasts as
   "ImmortalWrt".

CLI equivalent: `scp` the image to `/tmp`, then
`sysupgrade -n /tmp/….bin`.

### Coming from stock Xiaomi firmware

The stock web UI does not accept these images. Establish an
OpenWrt-family firmware first (the community-documented X-Wrt install
route), or — with a serial console — RAM-boot this port's initramfs
image and run sysupgrade from there
([RECOVERY.md](RECOVERY.md#ram-booting-an-initramfs-image-proven-procedure)).

### Between releases of this port

Plain sysupgrade, and keeping settings is fine. After the upgrade,
switch to the new release's ImageBuilder for any kernel-module work
(see below).

If the upgrader ever refuses an image as incompatible: stop and
investigate — do not force.

## Installing packages

**Ordinary packages** (LuCI apps, tools, daemons — anything not named
`kmod-*`) install normally through LuCI or `apk` from the official
ImmortalWrt feeds. Nothing special to do.

**Kernel modules (`kmod-*`) are different.** LuCI will report them as
*"not available in any repository"* — that is expected, not broken:
kernel modules must exactly match the running kernel, and this
firmware's kernel is self-built, so the official kmod feed can never
serve it. Instead, every release ships an **ImageBuilder** containing
every kernel module prebuilt for that exact kernel. Two ways to use
it (on x86_64 Linux — WSL or Docker on Windows works):

**A. Bake the module into the image and reflash** (recommended —
survives upgrades of the package list):

```bash
tar xf immortalwrt-imagebuilder-*.tar.zst && cd immortalwrt-imagebuilder-*/
```

```bash
make image PROFILE=xiaomi_miwifi-r3 PACKAGES="luci kmod-batman-adv luci-proto-batman-adv batctl-default"
```

A fresh `sysupgrade.bin` appears in `bin/targets/ramips/mt7620/` in
about a minute — flash it with "Keep settings" checked.

**B. Install directly, no reflash:** the ImageBuilder's `packages/`
directory holds every `kmod-*.apk`; copy the one you need (plus any
kmod dependencies) to the router and `apk add ./kmod-….apk`.

Two rules, both consequences of the kernel-matching requirement:

- Only use the ImageBuilder **from the release you are running** —
  never one from another release.
- After upgrading to a new release, redo kernel-module work with the
  new release's ImageBuilder.

## Common use cases

- **WireGuard VPN**:
  `PACKAGES="luci luci-proto-wireguard wireguard-tools"` — the
  matching `kmod-wireguard` is pulled in automatically.
- **batman-adv mesh**:
  `PACKAGES="luci kmod-batman-adv luci-proto-batman-adv batctl-default"`
- **USB storage**:
  `PACKAGES="luci kmod-usb-storage kmod-fs-ext4 block-mount"`
- **What's inside my image?** — the release's `….manifest` asset (or
  the one the ImageBuilder writes next to your custom image) lists
  every included package and version.

## Quirks

Things that look wrong but aren't — and the few that deserve
attention:

- **"Not available in any repository" for `kmod-*` in LuCI** — by
  design; use the release's ImageBuilder (previous section).
- **An occasional `nfc_ecc_verify` / `correct byte` line in the boot
  log or dmesg** — the NAND driver corrected a flipped bit, and the
  system then rewrites that block so it heals permanently. Normal
  flash aging, handled automatically. Only if the **same page number
  repeats across many boots** is something worth reporting.
- **Odd driver lines at every boot** (`!!! nand page size = 2048…`,
  `mtk_nand_probe: alloc…`) — harmless startup chatter from the NAND
  driver.
- **Log timestamps start in the past** on a freshly booted device —
  timestamps run from the firmware's build date until the clock syncs
  over the network (NTP), then jump to real time.
- **100 Mbit Ethernet ports** — a hardware property of this router,
  not a driver limitation.
- **After a cross-family install, everything is reset** — address
  `192.168.1.1`, user `root` with no password, WiFi open as
  "ImmortalWrt". Set the password and WiFi security first.
- **Never install Breed or any replacement bootloader** unless you
  have read [RECOVERY.md](RECOVERY.md#golden-rules) — no Breed build
  exists for this device, and a wrong bootloader is an unrecoverable
  brick.
