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

# The Mi Router R3 has two 4 MiB kernel slots sharing one UBI:
# kernel_stock (0x200000) and kernel (0x600000). Stock U-Boot boots the
# slot Xiaomi's boot flags select, "kernel" on a ported unit; breed and
# pb-boot ignore the flags and always boot kernel_stock. nand_do_upgrade
# writes CI_KERNPART only, so when one of those bootloaders is installed,
# or kernel_stock already holds an X-Wrt kernel, the new kernel is
# written to kernel_stock as well before the regular upgrade runs (the
# same approach as ipq806x's Xiaomi upgrade). Detection follows x-wrt.
xiaomi_miwifi_r3_boots_kernel_stock() {
	local boot="/dev/mtd$(find_mtd_index Bootloader)"
	local slot="/dev/mtd$(find_mtd_index kernel_stock)"

	dd if="$boot" bs=64 count=1 2>/dev/null | grep -qi breed && return 0
	dd if="$slot" bs=64 count=1 2>/dev/null | grep -o 'MIPS.*Linux' | grep -qi X-WRT && return 0
	dd if="$boot" 2>/dev/null | grep -qi pb-boot
}

xiaomi_miwifi_r3_do_upgrade() {
	local tar_file="$1"
	local cmd="$(identify_if_gzip "$tar_file")cat"
	local board_dir="$($cmd < "$tar_file" | tar tf - | grep -m 1 '^sysupgrade-.*/$')"
	board_dir="${board_dir%/}"

	if xiaomi_miwifi_r3_boots_kernel_stock; then
		echo "writing kernel to kernel_stock as well"
		$cmd < "$tar_file" | tar xOf - "$board_dir/kernel" | \
			mtd write - kernel_stock || {
			echo "failed to write kernel_stock"
			nand_do_upgrade_failed
		}
	fi
	nand_do_upgrade "$tar_file"
}

platform_do_upgrade() {
	local board=$(board_name)

	case "$board" in
	xiaomi,miwifi-r3)
		xiaomi_miwifi_r3_do_upgrade "$1"
		;;
	*)
		default_do_upgrade "$1"
		;;
	esac
}
