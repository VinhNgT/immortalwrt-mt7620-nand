# Provenance of the X-Wrt-derived files

The NAND driver, its Kconfig/Makefile hook and the device tree were
taken verbatim from [x-wrt/x-wrt](https://github.com/x-wrt/x-wrt),
`master` branch, at HEAD **0ea0580cdd203284d3a8a592fef4ef1558f44be0** (2026-11-20). They
are GPL-2.0 like the rest of the tree. X-Wrt rebases its entire patch
stack onto current OpenWrt, so its commit ids are not stable
references; the HEAD sha plus the blob hashes below identify the exact
content instead.

| file in this tree | x-wrt path | git blob hash as taken |
|---|---|---|
| `target/linux/ramips/files/drivers/mtd/maps/ralink_nand.c` | same | `3e30c76a709c5e21a0ecbbf3546e887e31758a19` |
| `target/linux/ramips/files/drivers/mtd/maps/ralink_nand.h` | same | `48bae135624c055b753344afd33357db81bab7f2` |
| `target/linux/ramips/dts/mt7620a_xiaomi_miwifi-r3.dts` | same | `a43f24372763eb2b18f4b4a7a8b647627faedd60` |
| `target/linux/ramips/patches-6.12/0038-mtd-ralink-add-mt7620-nand-driver.patch` | `patches-6.12/…` | `e7f33519fe449d2b8f78ae5939d181c0633f4537` |

`ralink_nand.c` in this tree additionally carries our mainline MTD ECC
accounting (`ecc_step_size`/`ecc_strength`/`bitflip_threshold`,
`ecc_stats.corrected`, and returning `max_bitflips = 1` instead of
`-EUCLEAN` directly) on top of the x-wrt content, so its current blob
hash differs from the one above by that delta
(`git log --oneline -- target/linux/ramips/files/drivers/mtd/maps/ralink_nand.c`).

The image recipe, `02_network` and the uboot-envtools entry were
ported by hand from x-wrt commit `f4fc1766f08a` and follow-ups (author
Chen Minqiang). `platform.sh` takes its bootloader detection from the
same source but writes the second kernel slot itself rather than
through x-wrt's `nand.sh` extension, which this tree does not carry
(see [PORT-NOTES.md](PORT-NOTES.md#what-differs-from-x-wrt--the-audit)).

`mt7620-nand/scripts/check-xwrt-drift.sh` downloads the current x-wrt
versions of the four files and compares their blob hashes against
this table, which it reads by column position — keep the table's
shape. Update the table (and the HEAD sha) whenever a sync brings new
content in; the procedure is in
[DEVELOPMENT.md](DEVELOPMENT.md#syncing-from-x-wrt).
