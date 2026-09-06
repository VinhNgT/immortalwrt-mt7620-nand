#
# Copyright (C) 2009 OpenWrt.org
#

SUBTARGET:=mt7620_nand
BOARDNAME:=MT7620 based boards with NAND flash
FEATURES+=usb ramdisk nand
CPU_TYPE:=24kc

DEFAULT_PACKAGES += kmod-rt2800-soc wpad-openssl swconfig

define Target/Description
	Build firmware images for Ralink MT7620 based boards with parallel
	NAND flash attached to the SoC's NAND controller.
endef
