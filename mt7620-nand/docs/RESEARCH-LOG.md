# Research log — how the conclusions were reached

This is the project's trial-and-error record: dead ends, corrected
assumptions, investigation narratives, and CI incidents, kept so that
future work doesn't re-make old mistakes. It is deliberately separate
from the reference documentation — read [PORT-NOTES.md](PORT-NOTES.md)
for *what is true* and [RECOVERY.md](RECOVERY.md) for *what to
do*; read this file before **re-researching** anything.

All dates 2026. Everything was verified against primary sources (git
history, raw file fetches, on-device inspection over serial), not
wikis.

Entries dated before 09-06 describe the predecessor repository,
[VinhNgT/immortalwrt-miwifi-r3](https://github.com/VinhNgT/immortalwrt-miwifi-r3)
(archived), where the port was a `patches/0001–0005` series plus an
"apply script" (`scripts/apply-r3-support.sh`) that grafted the port
onto a fresh upstream checkout in CI. "The installer" and "the apply
script" below mean that script. On 09-06 the port moved into this
fork as commits; the patch numbers map to commits as listed in
[PORT-NOTES.md](PORT-NOTES.md#the-port--13-touch-points).

## Timeline

- **08-29/30** — research: why the device fell out of OpenWrt, driver
  analysis, approach ranking (below). Repo scaffolded; first Docker
  and CI builds green on the first try.
- **08-30** — serial console established (3.3 V TTL, 115200 8N1);
  full NAND backup taken and md5-verified; U-Boot menu and CLI
  captured from the real unit.
- **08-31** — port proven from RAM (TFTP initramfs, zero flash
  writes): all 10 partitions, backup-identical reads, both radios,
  switch OK. Then installed permanently via sysupgrade (master/6.18
  build first, `v25.12.1`/6.12 the same day). pb-boot researched and
  declined. ECC defect root-caused and fixed (the ECC-report commit).
  ImageBuilder pipeline built, shaken out, fixed (the IB-feeds commit).
  CI caching added and audited through three runs. Docs consolidated.
- **09-06** — repository restructured: the patch-series + apply-script
  repository replaced by this fork of ImmortalWrt (branch `25.12` =
  tag `v25.12.1` + the port as commits). Reason: the series and the
  script were two hand-synchronised copies of the port and had
  already diverged (the series targeted master/6.18 only, the script
  handled 6.12 and 6.18), the script had three silent failure modes
  (anchor-based inserts with no post-check; a kernel-config loop that
  skipped symbols already marked "not set"), and the driver existed
  in three copies. The fork's first build reproduced the predecessor's
  `v25.12.1-r1` kernel package version and manifest exactly; it was
  published as pre-release `v25.12.1-r1` without a new hardware boot
  (no device at hand that day). Same day: the R3 moved into its own
  `mt7620-nand` subtarget (the shape the 2022 upstream review asked
  for), which also made the predecessor's "trim mt7620.mk to one
  device" script unnecessary — the ImageBuilder now offers one
  profile because the subtarget contains one device.

## Corrections — things that looked true and are wrong

Read before re-researching anything.

- **"There's a Breed for the R3" — there isn't.**
  `breed-mt7620-xiaomi-mini.bin` is the Mini (SPI-NOR);
  `breed-mt7621-xiaomi-r3g.bin` is the 3G (MT7621). The only
  NAND-capable Breed is for Atheros AR9344. A wrong-device bootloader
  on mtd0 is an unrecoverable brick.
- **"USB recovery will save me" — not on this unit.** The bootloader
  contains no USB/FAT support (full-partition strings scan: only
  `uboot.bin`, `test.bin`, `saveenv`). Xiaomi's USB recovery lived in
  the stock system in kernel0+rootfs0 — overwritten by X-Wrt.
- **"U-Boot has a bootloader RAM-test menu option" — not on this
  unit.** The real menu is 1/2/3/4/9 only; there is no option 7, and
  **option 9 is "Load Boot Loader code then write to Flash"** — it
  writes mtd0. Wiki lore about option layouts is not portable.
- **"A bootloader image can be dry-run from a running U-Boot" — no.**
  Warm-chaining pb-boot via `tftpboot`+`bootm` (transfer + CRC OK,
  jump taken) died silently: no console, no HTTP, no DHCP. Bootloaders
  expect cold-reset CPU state. The result says nothing about the
  image's health — which is precisely why it can't serve as a
  validation gate.
- **"OpenWrt never had an MT7620 NAND driver" — wrong.** In-tree
  through kernel 4.4; see the removal history in PORT-NOTES.md.
- **"mt7620 on 6.12 has a bad WiFi regression" — fixed.**
  openwrt/openwrt#19128 is closed/fixed, shipping in 25.12.1.
- **"mt7620 is being deprecated" — no.** Active 2026 development
  (upstream MediaTek ethernet PR #24557, PPE offload #24515).
- **"ImmortalWrt images always include LuCI" — release images do,
  `make defconfig` does not.** The first CI build booted SSH-only;
  `CONFIG_PACKAGE_luci=y` belongs in the seed.
- **A dormant second kernel slot is not a fallback.** mtd7 holds a
  CRC-valid stock 2.6.36 kernel whose rootfs no longer exists — it
  boots to a panic. Both slots share one UBI.
- **"pb-boot recovery is at 192.168.15.1" — wrong, it's 192.168.1.1.**
  Confirmed three ways: the binary's compiled-in env, and two
  independent tutorials. pb-boot also ignores Xiaomi's A/B boot flags
  entirely (no flag strings in the binary) — it always boots
  `kernel_stock` @ 0x200000, which is why x-wrt's sysupgrade mirrors
  the kernel there when it detects pb-boot/breed on mtd0.
- **"pb-boot can be verified against an official hash" — no longer
  possible.** `downloads.pangubox.com` is dead, the Wayback Machine
  never captured the file, no forum or repo ever published its hash,
  and GitHub code search finds nothing. The strongest available
  verification is internal (self-CRC + cold-boot entry code + the
  community record).
- **The first apply-script scaffold missed two touch points.** The
  original research counted eight; lifting the actual x-wrt device
  commit surfaced `02_network` (switch/MACs) and the uboot-envtools
  entry — without them the port would have had wrong network config
  and no fw_printenv. An eleventh (`nand.sh` CI_KERNPART_EXT) surfaced
  during the pb-boot safety research. Lesson: diff against the real
  upstream commit, not a mental model of it.

## The ECC investigation (the ECC-report commit)

Symptom: `nfc_ecc_verify: correct 512B data in N-th 512 bytes!`
warnings during every UBI attach — 3 pages on the first flash boot,
9 later the same day after heavy full-NAND read activity — while UBI
simultaneously reported 0 corrupted PEBs.

Root-caused from the log evidence alone:

- Every affected page was **page 0 of an erase block** — UBI
  erase-counter headers, written in mid-2022 per the UBI image
  sequence number, and never rewritten since. Classic retention /
  read-disturb population.
- Every event decoded as a clean **single-bit** correction. Random
  ECC-format garbage would decode that way with probability ~2^-12
  per 512-byte chunk — nine-for-nine rules out a format mismatch.
- Every corrected byte offset was **past the 64-byte EC header**, in
  0xFF padding — which is exactly why UBI counted 0 corrupted PEBs
  while the driver kept correcting.
- The driver swallowed every event: `_read` returned 0,
  `ecc_strength` unset, `ecc_stats` a commented-out TODO
  (`//ranfc_mtd->ecc_stats;`). So MTD never returned `-EUCLEAN`, UBI
  scrubbing never triggered, and the same aged pages were
  re-corrected on every read, forever.

Design constraint from the user: fix the root cause, don't suppress
the messages — the printks were deliberately left untouched.

Hardware verification went exactly as the mechanism predicts: the
first boot of an ECC-report build printed the corrections once
(driver reported → UBI scrubbed/rewrote the blocks), and a reinstall
of the same image booted with zero ECC lines — nothing left to
correct
([archived boot log](boot-logs/2026-08-31-first-boot-v25.12.1-p0004-ib-image.md)).

Related but distinct: one single-bit flip in `kernel_stock`
(page 0x6b7, byte 445 bit 1) was witnessed live during the RAM-boot
verification — corrected output still matched the backup md5. mtd7 is
not UBI-managed, so that flip stays until the partition is rewritten
(harmless; dormant slot).

## The ImageBuilder shakeout (the IB-feeds commit)

First real use of the CI-built ImageBuilder (a preset list including
wireguard, batman-adv, ddns, pbr, ttyd, upnp, https-dns-proxy, curl,
htop, nano) failed: every kmod resolved from the bundle, but the
plain userland packages came back "no such package".

Diagnosis: ImmortalWrt defaults to `CONFIG_IB_STANDALONE=y`, which
bundles every locally-built package but writes **no** `repositories`
file — the ImageBuilder is a sealed universe, and userland packages
the firmware build never compiled don't exist in it. Disabling
IB_STANDALONE is not an answer for an out-of-tree kernel: that
variant bundles only base-files/libc/kernel and lists the per-target
feed, whose kmods carry the official kernel's vermagic.

Proof before patch: hand-writing a `repositories` file listing only
the per-arch userland feeds produced a 217-package image in ~1 min —
kmods from the bundle at the exact kernel pin, userland fetched and
signature-verified from the official feeds (the IB already ships the
distro public keys). The IB-feeds commit then made the ImageBuilder emit
that file itself at build time.

Two empirical details worth remembering:

- The 25.12 release repo publishes **no `video` feed** even though
  `feeds.conf.default` lists one and defconfig sets
  `CONFIG_FEED_video=y`. A dead feed URL is only a warning to apk
  (tested), but it's noisy on every run — `CONFIG_FEED_video=m`
  in the seed emits the URL commented out (feeds marked `=m` are
  emitted as comments by upstream's own `FeedSourcesAppendAPK`).
- Every build is its own vermagic universe: two CI runs of the same
  upstream commit produced different kernel pins (`~b22042c4…` vs
  `~8e4ae743…`). Never mix kmods across builds; each run's
  ImageBuilder serves that run's image. *Corrected 09-06:* the pin is
  a hash of the kernel configuration and patches, so it is
  reproducible when those inputs are identical — the fork's first
  build, from the same tree and seed as the `~8e4ae743…` release,
  reproduced that pin exactly. The two differing runs had different
  seeds (the LuCI and ALL_KMODS changes landed between them). The
  rule stands because any kernel-side change moves the pin.

## CI incidents and pipeline decisions

- **Cache actions hand-rolled, not `klever1988/cachewrtbuild`.** The
  community action runs unpinned third-party code inside the job that
  produces firmware we flash — a supply-chain exposure. Its two real
  tricks were replicated in ~15 auditable lines: touch cached-tree
  mtimes after restore (stamps must be newer than the fresh clone),
  and cache `build_dir/host*` + `build_dir/toolchain-*` alongside
  `staging_dir` so make's stamp checks no-op natively.
- **`CONFIG_CCACHE=y` was silently dropped by defconfig** (first
  cached run built 1h37 with no compiler cache; the "saved ccache"
  was 283 bytes — just our conf file). Cause: the CCACHE Kconfig
  prompt is gated behind `DEVEL`; a seed value for a promptless
  symbol is discarded. Fix: `CONFIG_DEVEL=y`, plus post-defconfig
  greps in CI so any silently-dropped load-bearing symbol fails the
  run in minute two instead of costing a quiet hour.
- **Restoring toolchain trees across a config change fails.** After
  enabling ccache, the next run restored the pre-ccache toolchain
  cache; ccache wraps HOSTCC, which changes every package's
  configure fingerprint (`.configured_<hash>` stamps), so make
  re-ran configure on dirty restored trees — 19 minutes of doomed
  rebuilding, then binutils/gdb died in seconds. Fix: the toolchain
  cache key includes a hash of `config.seed`, so a seed change
  misses cleanly. Lesson: never replay OpenWrt staging/build trees
  across a config change.
- **Quiet-mode `failed to build` is undiagnosable** — that failure
  produced no usable error text. `CONFIG_BUILD_LOG=y` + a
  failure-only `build-logs` artifact fixed the class; the
  `|| make -j1 V=s` retry (which could burn an hour reproducing a
  failure serially) was then removed as redundant.
- **The "free disk space" purge step was removed** after measuring:
  current ubuntu runners have ~88 GB free on a 145 GB disk, the
  build peaks around 30–40 GB, and the purge cost 48–63 s per run to
  free headroom that was never needed. A `df -h /` report step
  remains so the margin is visible in every run's log.
- **The `dl/` cache is saved mid-job** right after `make download`
  (exact key per ref — release tarballs are frozen), and **ccache is
  saved `if: always()`** so failed runs still seed the retry. The
  combined community action can't do either.
- Measured timings: cold run 1h37 (toolchain 38 min, ALL_KMODS world
  54 min); ccache's first seeding run 1h52 (cold-cache overhead);
  ImageBuilder assembly from the artifact ~1 min.

## pb-boot — the full research trail (decision: not installed)

The convenience (recovery over LAN instead of the serial adapter)
does not justify one irreversible mtd0 write of a bootloader that can
never be byte-verified against an official copy. Stock U-Boot stays,
permanently. The record, in case this is ever revisited:

- **The file**: `pb-boot-xiaomi3-20181021-fd6329c.img`, 138,852 B,
  md5 `87c79881406cafa47853c734c76e1141`, sha256
  `c2235164b2dd676d9564defca9c8eefa3b447ac7f1b2966f0e1bef1145b7442a`,
  sha1 `a739d0f6607063543f208d734f4c6d5759d9b636`.
- **Provenance:** this exact filename is the community-standard R3
  bootloader — independently referenced by awaimai.com/2852, the
  cloud.tencent 1454352 tutorial, and a Vietnamese video tutorial
  (kamrul.dev uses the older `20180726-0d8505f`; a newer
  `20190317-61b6d33` also existed). The official source
  `downloads.pangubox.com/pb-boot/` is dead, never archived, and no
  hash was ever published ⇒ byte-verification is impossible,
  permanently. No R3 bootloader-brick reports exist anywhere; the
  "yellow LED loop" reports in the wild are self-built *firmware*
  missing the NAND driver — recovered through pb-boot itself.
- **Forensics:** internal uImage header + data CRCs valid (the file
  is self-verifying; accidental corruption excluded). Entry code is
  proper cold-boot MIPS (zeroes the register file first) — which also
  confirms the warm-chain dry-run failure was environmental, not
  evidence against the image. Ralink NAND driver (`ranand_*`) and a
  full HTTPD recovery are embedded. Compiled-in env: `bootdelay=1`,
  `ipaddr=192.168.1.1`, `serverip=192.168.1.100`.
- **Behavior (settled):** it contains none of Xiaomi's boot-flag
  strings — a binary constant scan finds `0x200000` 24 times and
  `0x600000`/`0xa00000` never. Its entire model is "firmware starts
  at 0x200000": it always boots `kernel_stock`, never mtd8.
- **Recovery mechanics** (binary + x-wrt issue tracker): the recovery
  environment is a mini-OS ("uOS v2.0") with HTTPD v3.0 and TFTP v1.1.
  The web upload validates firmware type before writing
  (`[httpd]Error firmware type.`), then erases/writes with a progress
  page. TFTP alternative: push the image as `firmware.bin` to
  192.168.1.1. Breed-style `/fullflash.bin` + `/eeprom.bin` endpoints
  exist in the binary — likely a full NAND dump over HTTP (never
  confirmed live). x-wrt commit `5c410e0095` ("sysupgrade compatable
  with breed") and issue #394 document the stale-slot failure that
  the dual-slot commit prevents; issue #409 shows an R3 flipping between
  PandoraBox and X-Wrt routinely; per ptpt52 in #404, returning to
  stock Xiaomi firmware is not supported from this ecosystem.
- **Residual unknowns:** whether recovery erases the whole
  0x200000→end region or only the upload's extent (stale UBI blocks
  could upset attach; non-brick — `mtd erase ubi` fixes it), and
  whether the `/fullflash.bin` download really works.
- The safe install sequence (each step gated on the last) is kept in
  RECOVERY.md's appendix.

## Questions that were open, now answered

- *Does the driver build at 6.18 on ImmortalWrt?* **Yes** — CI-built
  08-30, first try.
- *Has anyone booted an R3 on 6.18 with ImmortalWrt?* **Yes — 08-31**,
  initramfs from RAM: all 10 partitions, backup-identical reads, both
  radios on air, switch OK.
- *Does 6.12/25.12 work?* **Yes** — a combination previously compiled
  by no one (x-wrt's mt7620 has only `config-6.18`); built green and
  runs installed.
- *Will stock U-Boot load a uImage larger than the 4 MiB kernel slot
  via TFTP?* **Yes** — an 8.9 MB initramfs loads and boots fine from
  RAM; the 4 MiB limit is the flash slot, not TFTP. (Load high, at
  `0x84000000` — see RECOVERY.md.)
- *Does `bootcmd=tftp` give a serial-free recovery path?* Observed
  silent on a healthy boot; whether it fires after a kernel CRC
  failure remains untested (and untestable without inducing that
  state).

Still open: whether current OpenWrt maintainers would accept a proper
driver in 2026 (the 2022 refusal is Golle's); whether the NAND is
BMT-formatted (x-wrt's simple BBT works, mildly encouraging); whether
U-Boot passes `bootargs` (env has none — the `cmdlinepart`
mtd0-unlock trick was never tested, and is moot as long as stock
U-Boot is kept and mtd0 is never written).

## Ranked approaches (from the original research)

1. Mainline-quality driver + `mt7620-nand` subtarget → OpenWrt PR —
   months, refused twice, only worth it for its own sake.
2. Same quality bar, ImmortalWrt only — plausible; they ship the patch
   on 18.06-k5.4. No ImmortalWrt issue/PR mentions miwifi-r3.
3. Fork ImmortalWrt, lift the two x-wrt commits — **done: this
   repository is that fork** (on the 25.12 release rather than master,
   since 09-06).
4. Same against openwrt-25.12 (6.12) — **done** (08-31 in the
   predecessor, whose installer script was version-aware; the fork
   pins one release per branch).
5. Rebasable patch series + CI — **done 08-30 in the predecessor
   repository, replaced by the fork on 09-06** (see the timeline
   entry for why).
6. Stay on X-Wrt — the fallback that remains available.
7. SDK-backport packages onto 18.06-k5.4 — leaf packages only.
8. Kernel in NAND, rootfs on USB — fails on initramfs/extroot
   interaction and sysupgrade; not worth it.
9. 25.12 userspace on the 18.06 base — impossible; the 25.12 feeds
   are apk-v3 (`ADBd` container), opkg cannot read them, plus musl
   time64, vermagic, ucode-LuCI, procd/ubusd singletons.

## Community R3 references

ptpt52/lede-source, JustNoLimit/Xiaomi-MiWifi-R3-OpenWrt-Stable,
XFY9326/Xiaomi-R3-OpenWrt-Stable, astolfogit/miwifi-r3-production,
SourceForge mir3-openwrt (5.10 builds), OpenWrt forum thread 140403.
Stock-firmware STOK/`nvram` exploits do not apply to X-Wrt-family
firmware (no `nvram`).
