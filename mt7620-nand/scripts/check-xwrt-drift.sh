#!/bin/sh
# check-xwrt-drift.sh - has x-wrt changed the files this port took from it?
#
#   usage: mt7620-nand/scripts/check-xwrt-drift.sh [--hunks] [x-wrt-ref]
#          (default ref: master)
#
# x-wrt is never cloned: its patch stack is rebased continuously, so its
# commit ids are not stable, and it tracks OpenWrt master (a different
# kernel), so nothing would cherry-pick cleanly anyway. Instead this
# downloads the current x-wrt copies of the four files taken whole from
# it, hashes them the way git would, and compares against the blob
# hashes recorded in mt7620-nand/docs/PROVENANCE.md (the content as it
# was taken). Anything that differs is shown as a diff against this
# tree so it can be ported by hand. A file that can no longer be
# fetched counts as drift too: "not found" is not "unchanged". Exit
# status 1 when drift was found or a check could not be made.
#
# The other four x-wrt-derived items - the R3 image recipe, its
# 02_network case, its platform.sh case and its uboot-envtools line -
# are hunks inside files x-wrt rewrites at will, and platform.sh
# deliberately diverges (PORT-NOTES.md), so they are not hashed.
# --hunks prints x-wrt's current R3-related lines from those files for
# comparison by eye; the procedure is in DEVELOPMENT.md.
set -eu

HERE=$(cd "$(dirname "$0")/../.." && pwd)
HUNKS=0
[ "${1:-}" = "--hunks" ] && { HUNKS=1; shift; }
REF=${1:-master}
RAW="https://raw.githubusercontent.com/x-wrt/x-wrt/$REF"
API="https://api.github.com/repos/x-wrt/x-wrt/contents"
RAMIPS="target/linux/ramips"
PROV="$HERE/mt7620-nand/docs/PROVENANCE.md"
TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT

KV=$(sed -n 's/^KERNEL_PATCHVER:=\(.*\)$/\1/p' "$HERE/$RAMIPS/Makefile")

if [ $HUNKS = 1 ]; then
	# file, lines of context after each match
	for spec in "$RAMIPS/image/mt7620.mk 18" \
		    "$RAMIPS/mt7620/base-files/etc/board.d/02_network 6" \
		    "$RAMIPS/mt7620/base-files/lib/upgrade/platform.sh 10" \
		    "package/boot/uboot-tools/uboot-envtools/files/ramips 8"; do
		f=${spec% *}; after=${spec##* }
		echo "=== x-wrt $REF: $f"
		if curl -sSf "$RAW/$f" -o "$TMP/h" 2>/dev/null; then
			grep -n -B3 -A"$after" 'miwifi-r3' "$TMP/h" || echo "  (no miwifi-r3 lines)"
		else
			echo "  (could not fetch)"
		fi
		echo
	done
	exit 0
fi

recorded() {
	# blob hash recorded in PROVENANCE.md for a tree path (column 4 of its table)
	awk -F'|' -v p="$1" 'index($2, p) { gsub(/[` ]/, "", $4); print $4 }' "$PROV"
}

drift=0
check() {
	tree=$1 remote=$2
	if ! curl -sSf "$RAW/$remote" -o "$TMP/f" 2>/dev/null; then
		printf '%-72s %s\n' "$tree" "NOT FOUND at x-wrt $REF as $remote - moved or removed, find it by hand"
		drift=1
		return
	fi
	now=$(git hash-object "$TMP/f")
	was=$(recorded "$tree")
	if [ -z "$was" ]; then
		printf '%-72s %s\n' "$tree" "NO RECORDED HASH in PROVENANCE.md - fix the table"
		drift=1
	elif [ "$now" = "$was" ]; then
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

check $RAMIPS/files/drivers/mtd/maps/ralink_nand.c $RAMIPS/files/drivers/mtd/maps/ralink_nand.c
check $RAMIPS/files/drivers/mtd/maps/ralink_nand.h $RAMIPS/files/drivers/mtd/maps/ralink_nand.h
check $RAMIPS/dts/mt7620a_xiaomi_miwifi-r3.dts      $RAMIPS/dts/mt7620a_xiaomi_miwifi-r3.dts

# The Kconfig hook lives in x-wrt's per-kernel patches directory. Use the
# one for our kernel if x-wrt still has it, else the newest x-wrt has;
# if that cannot be determined the check below reports NOT FOUND.
p="$RAMIPS/patches-$KV/0038-mtd-ralink-add-mt7620-nand-driver.patch"
if ! curl -sSf -o /dev/null "$RAW/$p" 2>/dev/null; then
	newest=$(curl -sSf "$API/$RAMIPS?ref=$REF" 2>/dev/null \
		| sed -n 's/.*"name": *"patches-\([0-9.]*\)".*/\1/p' | sort -V | tail -n1)
	if [ -n "$newest" ]; then
		echo "note: x-wrt $REF has no patches-$KV; checking its newest, patches-$newest"
		p="$RAMIPS/patches-$newest/0038-mtd-ralink-add-mt7620-nand-driver.patch"
	fi
fi
check "$RAMIPS/patches-$KV/0038-mtd-ralink-add-mt7620-nand-driver.patch" "$p"

echo
if [ $drift = 0 ]; then
	echo "No drift: x-wrt's copies match the content recorded in mt7620-nand/docs/PROVENANCE.md."
else
	echo "Drift found: follow the x-wrt sync procedure in mt7620-nand/docs/DEVELOPMENT.md."
fi
exit $drift
