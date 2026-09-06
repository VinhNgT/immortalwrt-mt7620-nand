#
# MT7620A NAND Profiles
#
# Boards whose storage is parallel NAND on the SoC's own controller
# (CONFIG_MTD_NAND_MT7620, drivers/mtd/maps/ralink_nand.c). They live in
# their own subtarget so that the nand feature and the UBI/UBIFS kernel
# options never affect the mt7620 boards with SPI-NOR flash.
#
