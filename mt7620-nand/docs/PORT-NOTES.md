# Port notes — technical reference

What this port changes and why, written to stand alone. How these
conclusions were reached — including dead ends and corrected
assumptions — lives in [RESEARCH-LOG.md](RESEARCH-LOG.md). Operating
the device (flashing, recovery, serial) is covered by
[RECOVERY.md](RECOVERY.md).

## Why the device fell out of OpenWrt

The Xiaomi Mi Router 3 is an ordinary ramips/mt7620 board in every
respect but one: its 128 MiB of storage is **parallel raw NAND**, and
mainline Linux has no driver for the MT7620's NAND controller.
OpenWrt shipped an out-of-tree driver
(`drivers/mtd/maps/ralink_nand.c`, `CONFIG_MTD_NAND_MT7620=y`)
through kernel 4.4, used by two boards (Sercomm NA930, Ralink MT7620a
V22SG EVB), then lost it in the 4.4 → 4.9 bump:

| commit | date | what happened |
|---|---|---|
| `9c24227090` | 2017-02-13 | "ramips: add v4.9 support" — body reads, in full, "NAND support is missing" |
| `9bc9457b85` | 2017-06-01 | NAND restored — **MT7621 only** |
| `fddc78bc11` | 2017-07-05 | v4.9 bump deletes `patches-4.4/` incl. the 2,408-line NAND patch |
| `dea9922acd` | 2018-04-06 | drops 4.9, removing the dead `CONFIG_MTD_NAND_MT7620` line |
| `10f27c6f00` | 2020-04-01 | new clean MT7621 NAND driver |
| `2f2e81a4ea` | 2022-01-19 | moved to `files/drivers/mtd/nand/raw/mt7621_nand.c`, its location as of 2026 |

`compatible = "mtk,mt7620-nand"` still appears in two upstream DTS
files with no driver behind it.

Two attempts to bring the R3 back upstream were rejected:
openwrt/openwrt#597 (2018, by ptpt52 / Chen Minqiang, who went on to
found X-Wrt — which is why X-Wrt supports the R3 and OpenWrt does
not) and openwrt/openwrt#9344 (2022, where maintainer Daniel Golle
judged that a separate `ramips/mt7620-nand` subtarget would be needed
and called the driver "in very bad shape and unfit for submission
upstream"; 75 of 137 `IMAGE_SIZE` declarations in `mt7620.mk` are
≤ 8192k, so enabling NAND features subtarget-wide is a real risk to
other boards). ImmortalWrt's own `openwrt-18.06-k5.4` branch carries
the identical patch — this port effectively forward-ports
ImmortalWrt-lineage code.

This repository therefore carries the port **out of tree**, as a
fork of ImmortalWrt: a short commit series on top of an ImmortalWrt
release tag adds X-Wrt's driver and device support. (Until
2026-09-06 the same port was maintained in a separate repository as
a patch series plus an installer script applied to upstream
checkouts; see [RESEARCH-LOG.md](RESEARCH-LOG.md).)

## The NAND driver

`ralink_nand.c` (2,113 lines) is the legacy Ralink SDK driver,
maintained by X-Wrt. Its defining property explains both why upstream
refuses it and why it never breaks: it **bypasses the Linux rawnand
framework completely** — its own `struct ra_nand_chip`, its own
bad-block table, its own read/write/erase paths, registering a bare
`struct mtd_info`. It touches almost no kernel API, so it survived
5.10 → 6.18 essentially untouched, carrying `LINUX_VERSION_CODE`
guards for 6.12+ and a local `nand_ecclayout` replacing a struct the
kernel removed.

- Binding `compatible = "mtk,mt7620-nand"`; MTD device name `ra_nfc`.
- Partition probes `{ "cmdlinepart", "ofpart", NULL }` — a kernel
  command line can outrank the device tree.
- ECC: software Hamming over 512-byte steps, 1-bit correction.
- X-Wrt continuously rebases its patch stack onto current OpenWrt, so
  its commit SHAs are unstable; this branch carries the files as
  commits and records the X-Wrt HEAD they were taken from, plus the
  blob hashes, in [PROVENANCE.md](PROVENANCE.md).

### Why not extend OpenWrt's mt7621 NAND driver

MT7620 NFC and MT7621 NFI are different IP generations, not variants:

| | MT7620 NFC | MT7621 NFI |
|---|---|---|
| registers | `0x1000_0800`, 256-byte block | `0x1e003000` NFI + `0x1e003800` ECC engine |
| ECC | Hamming 24-bit/512B, 1-bit correction **in software** | hardware BCH, strength 4–12, hardware error readback |
| overlap | zero shared register offsets | — |

The register windows MT7621 uses are marked *Reserved* on MT7620.
None of the 1,344 mt7621 driver lines transfer; only `mtk_bmt` is
controller-independent.

## The port — 13 touch points

The port is the commit series on branch `25.12` on top of the
ImmortalWrt tag `v25.12.1` (see `git log v25.12.1..`). Touch points
1–11 derive from x-wrt commits `387988e8c956` (driver) and
`f4fc1766f08a` + follow-ups (device), author Chen Minqiang; 12 and 13
are this project's own fixes. The commits and the short names the
docs use for them:

| short name | commit subject | touch points |
|---|---|---|
| driver | `ramips: add mt7620-nand driver for NAND flash` | 1–3, 6, 7 |
| device | `ramips: add Xiaomi Mi Router R3 support` | 4, 5, 8–10 |
| dual-slot | `base-files: nand: support writing the kernel to a second partition` | 11 |
| ECC-report | `ramips: ralink_nand: report corrected bitflips so UBI can scrub` | 12 |
| IB-feeds | `imagebuilder: list remote userland feeds in standalone apk builds` | 13 |
| subtarget | `ramips: add mt7620-nand subtarget and move the Xiaomi Mi Router R3 to it` | 5–9 moved into `mt7620-nand/` |

The subtarget commit (2026-09-06) is the shape the upstream reviewer
asked for (below): everything device-specific lives in
`target/linux/ramips/mt7620-nand/` and `image/mt7620-nand.mk`, and
the shared `mt7620` subtarget is left as upstream ships it apart from
one line disabling the new Kconfig symbol. Touch points 5–9 below
name the files as they are after that commit.

1. `files/drivers/mtd/maps/ralink_nand.c` — the driver (new file)
2. `files/drivers/mtd/maps/ralink_nand.h` — (new file)
3. `patches-<kv>/0038-mtd-ralink-add-mt7620-nand-driver.patch` —
   18-line Kconfig/Makefile hook (6.12 and 6.18 variants
   byte-identical)
4. `dts/mt7620a_xiaomi_miwifi-r3.dts` — device tree; x-wrt master's
   version (modernized `nvmem-layout`; the 18.06-era one uses removed
   bindings)
5. `image/mt7620-nand.mk` — device/image recipe (formats below); the
   only device in the subtarget
6. `mt7620-nand/target.mk` — mt7620's target.mk with `nand` added to
   `FEATURES` (and `target/linux/ramips/Makefile` lists the subtarget)
7. `mt7620-nand/config-<kv>` — mt7620's kernel config plus
   `MTD_NAND_MT7620`, UBI, UBIFS + compression dependencies. Generated:
   `mt7620-nand/scripts/sync-subtarget-config.sh` merges
   `mt7620-nand/subtarget-kconfig.fragment` into mt7620's config with
   upstream's `scripts/kconfig.pl`, and CI fails if the committed file
   drifts from that merge
8. `mt7620-nand/base-files/lib/upgrade/platform.sh` — nand sysupgrade
   with bootloader/slot detection (only this subtarget's boards)
9. `mt7620-nand/base-files/etc/board.d/02_network` — switch ports
   (`1:lan 4:lan 0:wan 6@eth0`) + MACs from the `factory` partition
   at offset 0x28 (only this subtarget's boards; mt7620's other
   base-files are per-board case lists the R3 does not appear in, and
   ramips' shared base-files apply to every subtarget)
10. `package/boot/uboot-tools/uboot-envtools/files/ramips` —
    fw_printenv config (env on mtd1, offset 0x0, size 0x1000, sector
    0x20000)
11. `package/base-files/files/lib/upgrade/nand.sh` —
    `CI_KERNPART_EXT` support (the dual-slot commit): platform.sh's
    breed/pb-boot detection sets this variable so sysupgrade writes
    the kernel to **both** slots; it is an x-wrt extension that stock
    ImmortalWrt ignores, so without this patch the detection would be
    decorative and sysupgrade under breed/pb-boot would leave the
    booted slot stale. A guarded no-op under stock U-Boot.
12. `files/drivers/mtd/maps/ralink_nand.c` — ECC bitflip reporting
    (the ECC-report commit, ours — below)
13. `target/imagebuilder/Makefile` — userland feeds in the standalone
    apk ImageBuilder (the IB-feeds commit, ours — below)

`mt7620/config-<kv>` and `mt76x8/config-<kv>` additionally carry
`# CONFIG_MTD_NAND_MT7620 is not set` — both are `SOC_MT7620`, so the
new Kconfig symbol is visible there, and an explicit "not set" keeps
upstream's kernel-config refresh tooling from asking about it.

## The ECC-report commit — ECC corrections must reach MTD

The stock driver detects and corrects single-bit ECC errors but
swallows the event: its mtd `_read` hook returns 0, `ecc_strength`
is unset, and the `ecc_stats` hookup is a commented-out TODO. The
consequence is systemic: MTD core never returns `-EUCLEAN`, so UBI's
scrubbing — its rewrite-on-bitflip self-healing — never triggers, and
aging pages get silently re-corrected on every read, forever, until a
second bit flips in the same 512-byte step and the data is lost
(1-bit Hamming cannot correct two).

The fix counts successful corrections per read operation, returns the
kernel-standard max-bitflips-per-ECC-step value from `_read`, and
sets `ecc_strength = bitflip_threshold = 1`: with 1-bit correction,
any corrected step is already at the correction limit, so an
immediate `-EUCLEAN` → UBI scrub is the right response. This matches
mainline `nand_base.c` accounting conventions; corrections become
visible in `/sys/class/mtd/*/corrected_bits`.

Hardware-verified: aged single-bit flips in 2022-written UBI headers
were reported once on the first boot of a fixed build, UBI scrubbed
(rewrote) the blocks, and subsequent boots are silent
([archived boot log](boot-logs/2026-08-31-first-boot-v25.12.1-p0004-ib-image.md)).
Interpretation guide: an occasional `nfc_ecc_verify`/`correct byte`
message is a fresh flip self-healing; the same page repeating across
boots would warrant investigation. Kernel partitions (mtd7/mtd8) are
not UBI-managed and do not self-heal — a flip there persists until
the partition is rewritten. Candidate for upstreaming to x-wrt. The
investigation that established all this:
[RESEARCH-LOG.md](RESEARCH-LOG.md#the-ecc-investigation-patches0004).

## The IB-feeds commit — userland feeds for the standalone ImageBuilder

Because this port's kernel is self-built, its **vermagic** (the hash
kernel modules are matched against) can never equal the official
release's — official-feed kmods are permanently uninstallable, and
Linux without `CONFIG_MODULE_FORCE_LOAD` offers no override. The
repo's answer is `CONFIG_ALL_KMODS=y` (build **every** kmod with each
firmware) plus `CONFIG_IB=y` (every release ships an ImageBuilder
that bundles them all).

ImmortalWrt builds that ImageBuilder standalone
(`CONFIG_IB_STANDALONE=y`): every locally-built package is bundled,
but no `repositories` file is written, so plain **userland** packages
the firmware build didn't compile (curl, luci-app-\*, …) cannot be
installed at all — even though they are kernel-independent and
published in the official per-architecture feeds. Disabling
IB_STANDALONE would not help: that variant bundles only
base-files/libc/kernel and lists the per-target feed, whose kmods
carry the foreign official vermagic.

the IB-feeds commit makes the standalone apk ImageBuilder emit a
`repositories` file listing only the **per-arch userland feeds**
(`packages/mipsel_24kc/{base,packages,luci,routing,telephony}`),
mirroring upstream's `FeedSourcesAppendAPK` minus its per-target and
kmods lines. Kernel-dependent packages keep resolving exclusively
from the bundled `packages/` directory (apk pins the exact kernel
version, so a foreign kmod cannot sneak in even if a remote feed
offered one); any release userland package installs on demand,
signature-verified against the distro public keys the ImageBuilder
already ships in `keys/`. Candidate for upstreaming to ImmortalWrt.

Related seed setting: `CONFIG_FEED_video=m` — the 25.12 release repo
publishes no `video` feed, and `=m` emits its URL commented out (in
the router's own feed list too) instead of producing a 404 warning on
every package-index update.

Operating rules that follow from the vermagic design:

- kmods only ever come from the same release as the installed image;
- kernel-side changes (driver patches, kernel config) need a new
  release, which ships a new ImageBuilder.

## Kernel/target choice

Branch `25.12` pins the ImmortalWrt `v25.12.1` release (kernel 6.12).
That driver/kernel combination had been compiled by no one before
August 2026 — x-wrt's mt7620 carries only `config-6.18` — and it was
built in CI and booted on real hardware that month. The driver was
also built and booted on ImmortalWrt master with kernel 6.18 in
August 2026 (the kernel X-Wrt ships for this board), so a future
kernel bump starts from a known-good combination; only the release
line is maintained here.

## Image formats and slot logic

`mt7620.mk` produces:

- `sysupgrade.bin` — nand sysupgrade tar + metadata (the normal
  upgrade path)
- `initramfs-kernel.bin` — complete system in one uImage, for
  RAM-booting via TFTP (testing/recovery; writes nothing)
- `kernel1.bin` / `rootfs0.bin` — the split pieces
- `factory.bin` — kernel padded to 4 MiB + UBI (single-image format
  used by pb-boot/breed web recovery)
- `breed-factory.bin` — kernel **twice** (each padded to 4 MiB) + UBI
  — populates both kernel slots at once

Slot logic (from `platform.sh` + the dual-slot commit): the R3 has two
4 MiB kernel slots, `kernel_stock` (mtd7, at 0x200000) and `kernel`
(mtd8, at 0x600000), sharing one UBI. Stock U-Boot honors Xiaomi's
A/B flag and boots mtd8 on ported units; pb-boot/breed always boot
mtd7. sysupgrade detects which bootloader is on mtd0 and writes the
kernel to the slot(s) that bootloader will actually read.

## Upstreaming outlook

The 2022 upstream review (openwrt/openwrt#9344) asked for two things:
a separate `ramips/mt7620-nand` subtarget instead of enabling `nand`
on the shared mt7620 one, and a driver rewritten on the rawnand
framework. The subtarget exists here since 2026-09-06 (the subtarget
commit above), so the remaining gap to a mainline-quality submission
is the driver rewrite. Encouragingly, mt7621 already ships
`FEATURES+=nand` with 46 UBI recipes, so the
ubinize/UBI/nand_do_upgrade pipeline is proven in this target tree.
The ECC-report commit (for x-wrt) and the IB-feeds commit (for
ImmortalWrt) are self-contained upstream candidates independent of
that question.

## Reference links

- x-wrt: github.com/x-wrt/x-wrt · images: downloads.x-wrt.com/rom/
- ImmortalWrt: github.com/immortalwrt/immortalwrt (kernels as of
  2026-09: master = 6.18, openwrt-25.12 = 6.12, openwrt-18.06-k5.4 =
  5.4)
- OpenWrt table of hardware: openwrt.org/toh/xiaomi/mir3 (listed
  unsupported)
- Community history and further links:
  [RESEARCH-LOG.md](RESEARCH-LOG.md)
