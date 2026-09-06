# Mi Router 3 — recovery runbook

Backup, serial console, and every path back from a bad flash on a
Xiaomi Mi Router 3 (R3) running this project's firmware. Normal
installation and upgrades are in [GUIDE.md](GUIDE.md); this file is
for prevention and repair. Everything here was established by direct
on-device inspection and live serial sessions on one real unit on
2026-08-30 and 2026-08-31 ("the tested unit" below), not from wikis —
where behavior could plausibly vary between units, that is noted.
(The maintainer's device-specific data — serial number, backup
checksums, local paths — is kept in a git-ignored file,
`mt7620-nand/PRIVATE-NOTES.md`, and is not published.)

## Standing facts

- Bootloader (mtd0): **stock Ralink U-Boot 1.1.3** (2016 build),
  uImage-wrapped. This runbook never modifies it.
- The tested unit's U-Boot env, as found, suited recovery work:
  `uart_en=1`, `boot_wait=on`, `bootdelay=5`, `ipaddr=192.168.1.1`,
  `serverip=192.168.1.3`, and `flag_boot_rootfs=1` → boots the
  `kernel` slot (mtd8). Inspect yours with `fw_printenv` before
  relying on it.
- mtd0 is read-only under Linux (DTS `read-only`) — by design; keep
  it that way.
- Kernel slots: on a unit converted from Xiaomi's firmware, mtd7
  `kernel_stock` typically holds Xiaomi's original 2.6.36 kernel —
  CRC-valid but its root filesystem was overwritten by the
  conversion, so it is **not a fallback**. mtd8 `kernel` is the live
  slot under stock U-Boot.
- The stock bootloader has **no USB and no web recovery**. Serial is
  the backstop (any 3.3 V USB-TTL adapter, 115200 8N1).
- NAND: ESMT F59L1G81LA (128 MiB). Single-bit retention flips
  accumulate in long-unwritten pages; the driver's ECC corrects them
  on every read, and builds with the ECC-report commit additionally report
  them to MTD so UBI scrubs (rewrites) the affected blocks —
  hardware-verified
  ([log](boot-logs/2026-08-31-first-boot-v25.12.1-p0004-ib-image.md)).
  An occasional `nfc_ecc_verify`/`correct byte` message is a
  fresh retention flip being corrected — it self-heals via scrub and
  shows in `/sys/class/mtd/*/corrected_bits`; only *the same page
  repeating across boots* warrants a look. mtd7/mtd8 are not
  UBI-managed — a flip there stays until that partition is rewritten
  (harmless in the dormant slot).

## The backup — make one before anything else

Before the first flash, take a full NAND dump (RAM-boot an initramfs
image — procedure below — then `dd` every `/dev/mtdN` to USB or scp
them off) and verify checksums on the PC. Keep two copies, offline.
mtd3 `factory` holds the RF calibration and MACs and is
**irreplaceable** — no download can ever restore it.

| mtd | name | size | notes |
|---|---|---|---|
| 0 | Bootloader | 256 KiB | stock U-Boot 1.1.3 |
| 1 | Config | 256 KiB | U-Boot env |
| 2 | Bdata | 256 KiB | serial number, keys |
| 3 | **factory** | 256 KiB | **RF calibration + MACs — irreplaceable** |
| 4–6 | crash / crash_syslog / reserved0 | 256 KiB each | |
| 7 | kernel_stock | 4 MiB | stock 2.6.36 kernel (dead slot) |
| 8 | kernel | 4 MiB | live kernel slot |
| 9 | ubi | 118 MiB | rootfs + overlay |

## Golden rules

1. **Never write mtd0.** All install/recovery paths below work
   without touching it. (pb-boot would require it — declined; see
   appendix.)
2. Never install Breed — no R3 build exists; a wrong-device
   bootloader is an unrecoverable brick.
3. Never let anything erase mtd3 (`factory`).
4. Serial: 3.3 V TTL, RX→TX, TX→RX, GND→GND, **VCC not connected**.
5. In the U-Boot menu, **option 9 writes the bootloader to flash** —
   never select it casually. There is no RAM-test menu option.
6. **Never power off mid-write.** Flashing over WiFi is fine —
   sysupgrade uploads the whole image to RAM before writing — but
   bootloader-level recovery (U-Boot, TFTP) only exists on the wired
   ports, so keep a LAN cable within reach.

## Recovery ladder

Any failure state short of a destroyed bootloader is recoverable:

1. **Firmware misbehaves but boots** → sysupgrade to a known-good
   image (ImmortalWrt or X-Wrt).
2. **Firmware doesn't boot** → serial → U-Boot → RAM-boot an
   initramfs image (below) → repair from Linux: `mtd write` the
   relevant partitions from the backup, or run sysupgrade from the
   RAM-booted system.
3. **Byte-exact return to whatever was backed up** (the firmware
   installed before this project's) → RAM-boot any initramfs, copy
   the backed-up `mtd8.bin` + `mtd9.bin` over (USB stick or scp), then
   `mtd write mtd8.bin kernel && mtd write mtd9.bin ubi`.
   (`factory`/`Bdata` only if actually damaged.)

## Serial + U-Boot reference (as captured on the tested unit, 2026-08-30)

Wiring per rule 4; any terminal at 115200 8N1, flow control off.
Interrupt within 5 s of power-on. The real menu:

```
1: Load system code to SDRAM via TFTP.        (RAM-boot, writes nothing)
2: Load system code then write to Flash via TFTP.
3: Boot system code via Flash (default).
4: Entr boot command line interface.          (MT7620 # prompt)
9: Load Boot Loader code then write to Flash via TFTP.   ** WRITES mtd0 **
```

CLI commands available: `tftpboot`, `bootm`, `go`, `nand`, `md`,
`mm`, `nm`, `printenv`, `setenv`, `saveenv`, `reset`, `version`,
`mdio`, `rf`. Rule of thumb: `setenv` without `saveenv` is RAM-only
and safe.

### TFTP server gotchas (Windows host, tftpd64)

- Host static on the `serverip` address (`192.168.1.3/24` on the
  tested unit), cable into a **LAN** port.
- The link has no gateway → Windows treats it as
  **Public/Unidentified** → the firewall silently eats TFTP (and
  ICMP echo, so ping tests mislead). Symptom signature: U-Boot prints
  `Got ARP REPLY` then `T T T…` timeouts — ARP works, TFTP dies on
  the host. Fix: allow tftpd64 on all firewall profiles, or
  temporarily `netsh advfirewall set allprofiles state off`
  (re-enable after).
- Check tftpd64's "Server interfaces" is bound to the right adapter
  and the base directory holds the image.
- A missing file comes back as an explicit error, not timeouts.

## RAM-booting an initramfs image (proven procedure)

Boots a complete firmware entirely from RAM — **zero flash writes**;
a power-cycle returns to the flashed system. This is both the test
harness and the recovery vehicle.

1. Put `…initramfs-kernel.bin` in the TFTP root under a short name
   (`r3.bin`).
2. Menu → `4`, then:
   ```
   tftpboot 84000000 r3.bin
   bootm 84000000
   ```
   Load **high** (`0x84000000`): the kernel decompresses to
   `0x80000000`, and a multi-MB image at the default `0x80100000`
   would overlap its own destination. Images well past the 4 MiB
   flash-slot limit load fine this way (8.9 MB verified — the limit
   is the flash slot, not TFTP).
3. A root shell appears on serial; LAN comes up as `192.168.1.1`.

This is the procedure that verified this project's firmware on
2026-08-31 before anything was flashed: a RAM-booted image showed all
10 partitions with the exact stock layout, partition reads
byte-identical to the backup, and both radios working (details in
[RESEARCH-LOG.md](RESEARCH-LOG.md#timeline)). Use it the same way to
vet any new build.

## Reverting to X-Wrt (or to whatever was installed before)

- From a working system: sysupgrade (fresh config) with the X-Wrt
  image from `downloads.x-wrt.com/rom/`, or with any other
  OpenWrt-family image for this device.
- From a broken system: recovery ladder step 2 or 3.

## Appendix: pb-boot — researched, declined

pb-boot is the community replacement bootloader for the R3
(PandoraBox lineage). It would add LAN-cable web recovery — hold
reset at power-on → upload page at `http://192.168.1.1` accepting
this project's `breed-factory.bin` (or a TFTP push of it as
`firmware.bin`).

**Decision (2026-08-31): not installing.** That convenience does not
justify the one irreversible mtd0 write of a binary that can never be
byte-verified — its official source is dead and no hash was ever
published. Serial + RAM-boot + the backup already cover every failure
mode. The full forensic record (provenance, binary analysis, verified
behavior, residual unknowns) is in
[RESEARCH-LOG.md](RESEARCH-LOG.md#pb-boot--the-full-research-trail-decision-not-installed).

Facts that matter even without installing it:

- pb-boot/breed always boot `kernel_stock` (mtd7), ignoring Xiaomi's
  A/B flags. This project's sysupgrade handles that: the dual-slot commit
  (`CI_KERNPART_EXT`) makes it write the kernel to **both** slots
  when it detects such a bootloader on mtd0 — a guarded no-op under
  stock U-Boot, kept for any R3 owner who does run pb-boot/breed.
- The community image circulates as
  `pb-boot-xiaomi3-20181021-fd6329c.img` (138,852 B, md5
  `87c79881406cafa47853c734c76e1141`, sha256
  `c2235164b2dd676d9564defca9c8eefa3b447ac7f1b2966f0e1bef1145b7442a`)
  — hashes recorded so a copy can at least be matched against the
  one analyzed in August 2026.

**If ever installing — the safe sequence** (each step gated on the
last):

1. Only from a running ImmortalWrt built **with the dual-slot commit** —
   without it, every sysupgrade under pb-boot leaves the booted slot
   stale.
2. Pre-stage slot 0 so pb-boot has something to boot:
   `mtd write kernel1.bin kernel_stock`, then verify the read-back.
3. Serial attached, stable power: U-Boot menu option `9`, send the
   pb-boot `.img` verbatim (uImage header included). **Do not power
   off during the write.**
4. Reboot → pb-boot boots mtd7 → same UBI rootfs as before.
5. Test recovery before trusting it: hold-reset power-on →
   `192.168.1.1` — inspect the page, then reboot without uploading.
6. Thereafter recovery = upload `breed-factory.bin` via the web page
   (or TFTP-push as `firmware.bin`); sysupgrades keep both slots
   current automatically.
