#!/bin/sh
# check-xwrt-drift.sh - has x-wrt changed the files this port took from it?
#
#   usage: mt7620-nand/scripts/check-xwrt-drift.sh [x-wrt-ref]   (default: master)
#
# x-wrt is never cloned: its patch stack is rebased continuously, so its
# commit ids are not stable, and it tracks OpenWrt master (a different
# kernel), so nothing would cherry-pick cleanly anyway. Instead this
# downloads the current x-wrt copies of the four ported files, hashes
# them the way git would, and compares against the blob hashes recorded
# in mt7620-nand/docs/PROVENANCE.md (the content as it was taken). Anything that
# differs is shown as a diff against this tree so it can be ported by
# hand as a new commit. Exit status 1 when drift was found.
set -eu

HERE=$(cd "$(dirname "$0")/../.." && pwd)
REF=${1:-master}
RAW="https://raw.githubusercontent.com/x-wrt/x-wrt/$REF/target/linux/ramips"
PROV="$HERE/mt7620-nand/docs/PROVENANCE.md"
TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT

KV=$(sed -n 's/^KERNEL_PATCHVER:=\(.*\)$/\1/p' "$HERE/target/linux/ramips/Makefile")

recorded() {
	# blob hash recorded in PROVENANCE.md for a tree path
	awk -F'|' -v p="$1" 'index($2, p) { gsub(/[` ]/, "", $4); print $4 }' "$PROV"
}

drift=0
check() {
	tree=$1 remote=$2
	if ! curl -sSf "$RAW/$remote" -o "$TMP/f" 2>/dev/null; then
		printf '%-72s %s\n' "$tree" "not present at x-wrt $REF"
		return
	fi
	now=$(git hash-object "$TMP/f")
	was=$(recorded "$tree")
	if [ "$now" = "$was" ]; then
		printf '%-72s %s\n' "$tree" "unchanged"
	else
		printf '%-72s %s\n' "$tree" "CHANGED ($was -> $now)"
		drift=1
		diff -u "$HERE/$tree" "$TMP/f" > "$TMP/$(basename "$tree").diff" || true
		echo "  --- diff vs this tree (theirs is '+'; our ECC-report hunk shows as '-' in ralink_nand.c):"
		sed 's/^/  /' "$TMP/$(basename "$tree").diff"
	fi
}

echo "x-wrt ref: $REF   (kernel here: $KV)"
echo "recorded provenance: $(sed -n 's/.*at HEAD \*\*\([0-9a-f]\{40\}\)\*\*.*/\1/p' "$PROV" | head -n1)"
echo "x-wrt $REF HEAD:     $(git ls-remote https://github.com/x-wrt/x-wrt.git "refs/heads/$REF" | cut -f1 | head -n1)"
echo

check target/linux/ramips/files/drivers/mtd/maps/ralink_nand.c  files/drivers/mtd/maps/ralink_nand.c
check target/linux/ramips/files/drivers/mtd/maps/ralink_nand.h  files/drivers/mtd/maps/ralink_nand.h
check target/linux/ramips/dts/mt7620a_xiaomi_miwifi-r3.dts       dts/mt7620a_xiaomi_miwifi-r3.dts
# the Kconfig hook lives per kernel version upstream; try ours, then the newest
p="patches-$KV/0038-mtd-ralink-add-mt7620-nand-driver.patch"
curl -sSf -o /dev/null "$RAW/$p" 2>/dev/null || p="patches-6.18/0038-mtd-ralink-add-mt7620-nand-driver.patch"
check "target/linux/ramips/patches-$KV/0038-mtd-ralink-add-mt7620-nand-driver.patch" "$p"

echo
[ $drift = 0 ] && echo "No drift: x-wrt's copies match the content recorded in mt7620-nand/docs/PROVENANCE.md." \
              || echo "Drift found: port what is relevant as a new commit, then update mt7620-nand/docs/PROVENANCE.md."
exit $drift
