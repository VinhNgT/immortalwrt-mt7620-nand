#!/bin/sh
# sync-subtarget-config.sh - regenerate (or verify) the mt7620_nand kernel
# config from mt7620's config plus this project's fragment.
#
#   usage: mt7620-nand/scripts/sync-subtarget-config.sh [--check]
#
# target/linux/ramips/mt7620_nand/config-<kv> is by definition
# "mt7620's config-<kv> with the NAND/UBI symbols from
# mt7620-nand/subtarget-kconfig.fragment on top", merged with the tree's
# own scripts/kconfig.pl so the result has OpenWrt's canonical layout.
# Run it after every upstream rebase (mt7620's config moves with the
# kernel); CI runs it with --check and fails if the committed file has
# drifted from what the merge produces. Exit 1 on drift in --check mode.
set -eu

HERE=$(cd "$(dirname "$0")/../.." && pwd)
R="$HERE/target/linux/ramips"
KV=$(sed -n 's/^KERNEL_PATCHVER:=\(.*\)$/\1/p' "$R/Makefile")
BASE="$R/mt7620/config-$KV"
OUT="$R/mt7620_nand/config-$KV"
FRAG="$HERE/mt7620-nand/subtarget-kconfig.fragment"

[ -f "$BASE" ] || { echo "ERROR: $BASE not found" >&2; exit 1; }

TMP=$(mktemp); trap 'rm -f "$TMP"' EXIT
perl "$HERE/scripts/kconfig.pl" '+' "$BASE" "$FRAG" > "$TMP"

if [ "${1:-}" = "--check" ]; then
	if diff -u "$OUT" "$TMP"; then
		echo "mt7620_nand/config-$KV is in sync with mt7620/config-$KV + fragment"
	else
		echo "ERROR: $OUT differs from mt7620/config-$KV + fragment - run $0" >&2
		exit 1
	fi
else
	cp "$TMP" "$OUT"
	echo "wrote $OUT (mt7620/config-$KV + $(grep -c '^[^#]' "$FRAG") symbols)"
fi
