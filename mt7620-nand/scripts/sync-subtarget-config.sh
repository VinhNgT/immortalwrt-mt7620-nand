#!/bin/sh
# sync-subtarget-config.sh - regenerate (or verify) the mt7620_nand kernel
# config from mt7620's config plus this project's fragment, and check
# that every dependency gate on the mt7620 subtarget name also names
# mt7620_nand.
#
#   usage: mt7620-nand/scripts/sync-subtarget-config.sh [--check]
#
# target/linux/ramips/mt7620_nand/config-<kv> is by definition
# "mt7620's config-<kv> with the NAND/UBI symbols from
# mt7620-nand/subtarget-kconfig.fragment on top", merged with the tree's
# own scripts/kconfig.pl so the result has OpenWrt's canonical layout.
# Run it after every upstream rebase (mt7620's config moves with the
# kernel); CI runs it with --check after installing the feeds, so the
# gate scan below covers them too, and fails if the committed file has
# drifted from what the merge produces. Exit 1 on drift in --check mode.
#
# The subtarget is mt7620 plus NAND and nothing less, and in ramips a
# subtarget name means an SoC: packages and image code gate on
# TARGET_ramips_mt7620, or on $(SUBTARGET) being mt7620. Every such gate
# must name mt7620_nand too, or the package silently becomes unavailable
# there (defconfig drops an unsatisfiable default package without a word,
# so nothing else would notice; kmod-rt2800-soc, the SoC's 2.4 GHz
# driver, is such a default package). Both modes list any gate that
# lacks the name and exit 1; the fix is adding the name in the file shown.
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

status=0
if [ "${1:-}" = "--check" ]; then
	if diff -u "$OUT" "$TMP"; then
		echo "mt7620_nand/config-$KV is in sync with mt7620/config-$KV + fragment"
	else
		echo "ERROR: $OUT differs from mt7620/config-$KV + fragment - run $0" >&2
		status=1
	fi
else
	cp "$TMP" "$OUT"
	echo "wrote $OUT (mt7620/config-$KV + $(grep -c 'CONFIG_' "$FRAG") symbols)"
fi

# Gates on the subtarget name that do not also name mt7620_nand:
# Kconfig-style symbols wherever packages and targets are defined, and
# make-level comparisons of $(SUBTARGET) in this target's image code.
cd "$HERE"
dirs="package target/linux/ramips include"
[ -d feeds ] && dirs="$dirs feeds"
gates=$( {
	grep -rnE --exclude-dir=.git 'TARGET_ramips_mt7620([^_a-zA-Z0-9]|$)' $dirs 2>/dev/null || true
	grep -rnE --exclude-dir=.git 'SUBTARGET.*[^_a-zA-Z0-9]mt7620([^_a-zA-Z0-9]|$)' \
		target/linux/ramips/image target/linux/ramips/modules.mk include 2>/dev/null || true
} | grep -v 'mt7620_nand' || true )
if [ -n "$gates" ]; then
	echo "ERROR: these gate on the mt7620 subtarget without naming mt7620_nand - add it:" >&2
	echo "$gates" | sed 's/^/  /' >&2
	status=1
else
	echo "every gate on the mt7620 subtarget name also names mt7620_nand"
fi
exit $status
