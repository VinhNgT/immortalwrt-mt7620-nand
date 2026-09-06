#
# MT7620A NAND Profiles
#
# Boards whose storage is parallel NAND on the SoC's own controller
# (CONFIG_MTD_NAND_MT7620, drivers/mtd/maps/ralink_nand.c). They live in
# their own subtarget so that the nand feature and the UBI/UBIFS kernel
# options never affect the mt7620 boards with SPI-NOR flash.
#

define Device/xiaomi_miwifi-r3
  SOC := mt7620a
  BLOCKSIZE := 128k
  PAGESIZE := 2048
  KERNEL_SIZE := 4096k
  IMAGE_SIZE := 32768k
  UBINIZE_OPTS := -E 5
  IMAGES += kernel1.bin rootfs0.bin breed-factory.bin factory.bin
  IMAGE/kernel1.bin := append-kernel | check-size $$(KERNEL_SIZE)
  IMAGE/rootfs0.bin := append-ubi | check-size
  IMAGE/sysupgrade.bin := sysupgrade-tar | append-metadata
  IMAGE/factory.bin := append-kernel | pad-to $$(KERNEL_SIZE) | append-ubi | check-size
  IMAGE/breed-factory.bin := append-kernel | pad-to $$(KERNEL_SIZE) | \
	append-kernel | pad-to $$(KERNEL_SIZE) | \
	append-ubi | check-size
  DEVICE_VENDOR := Xiaomi
  DEVICE_MODEL := Mi Router R3
  DEVICE_PACKAGES := kmod-mt76x2 kmod-usb2 kmod-usb-ohci uboot-envtools
endef
TARGET_DEVICES += xiaomi_miwifi-r3
