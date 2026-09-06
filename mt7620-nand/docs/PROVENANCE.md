# Provenance of the X-Wrt-derived files

The NAND driver, its Kconfig/Makefile hook and the device tree were
taken verbatim from [x-wrt/x-wrt](https://github.com/x-wrt/x-wrt),
`master` branch, at HEAD **3d76e35c18d0efd727fa8f02f8b4ad4f9009c75f** (2026-08-30). They
are GPL-2.0 like the rest of the tree. X-Wrt rebases its entire patch
stack onto current OpenWrt, so its commit ids are not stable
references; the HEAD sha plus the blob hashes below identify the exact
content instead.

| file in this tree | x-wrt path | git blob hash as taken |
|---|---|---|
| `target/linux/ramips/files/drivers/mtd/maps/ralink_nand.c` | same | `e80dcaf1d60d484c41027ec13dfb9b8831ddfa6a` |
| `target/linux/ramips/files/drivers/mtd/maps/ralink_nand.h` | same | `b94dc09479ad0afd788eefe0c5b5e83eec52fb44` |
| `target/linux/ramips/dts/mt7620a_xiaomi_miwifi-r3.dts` | same | `a43f24372763eb2b18f4b4a7a8b647627faedd60` |
| `target/linux/ramips/patches-6.12/0038-mtd-ralink-add-mt7620-nand-driver.patch` | `patches-6.12/…` | `e7f33519fe449d2b8f78ae5939d181c0633f4537` |

`ralink_nand.c` in this tree additionally carries the ECC-report
commit on top of the x-wrt content, so its current blob hash differs
from the one above by exactly that commit
(`git log --oneline -- target/linux/ramips/files/drivers/mtd/maps/ralink_nand.c`).

The image recipe, `platform.sh`, `02_network`, uboot-envtools entry
and the dual-slot `nand.sh` extension were ported by hand from x-wrt
commit `f4fc1766f08a` and follow-ups (author Chen Minqiang).

`mt7620-nand/scripts/check-xwrt-drift.sh` downloads the current x-wrt
versions of the four files and compares their blob hashes against
this table. Update the table (and the HEAD sha) whenever a sync brings
new content in.
