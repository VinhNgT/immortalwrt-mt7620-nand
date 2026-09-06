#
# Copyright (C) 2010 OpenWrt.org
#

PART_NAME=firmware
REQUIRE_IMAGE_METADATA=1

RAMFS_COPY_BIN='fw_printenv fw_setenv'
RAMFS_COPY_DATA='/etc/fw_env.config /var/lock/fw_printenv.lock'

platform_check_image() {
	return 0
}

platform_do_upgrade() {
	local board=$(board_name)

	case "$board" in
	xiaomi,miwifi-r3)
		# this make it compatible with breed
		dd if=/dev/mtd0 bs=64 count=1 2>/dev/null | grep -qi breed && CI_KERNPART_EXT="kernel_stock"
		dd if=/dev/mtd7 bs=64 count=1 2>/dev/null | grep -o MIPS.*Linux | grep -qi X-WRT && CI_KERNPART_EXT="kernel_stock"
		dd if=/dev/mtd7 bs=64 count=1 2>/dev/null | grep -o MIPS.*Linux | grep -qi NATCAP && CI_KERNPART_EXT="kernel0_rsvd"
		dd if=/dev/mtd0 2>/dev/null | grep -qi pb-boot && CI_KERNPART_EXT="kernel_stock"
		nand_do_upgrade "$1"
		;;
	*)
		default_do_upgrade "$1"
		;;
	esac
}
