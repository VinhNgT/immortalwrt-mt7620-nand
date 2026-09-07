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
#
# A gate can also be composed: a package sets BUILD_SUBTARGET:=mt7620 and
# a shared include (include/u-boot.mk) glues that into the symbol
# TARGET_ramips_mt7620 itself, so the literal symbol never appears in
# the package and the grep above cannot see it. Composed gates are
# reported, not failed: the only ones in the tree are the U-Boot builds
# for the MT7620 evaluation boards, and such a gate is device-bound (the
# package exists for the boards named in its BUILD_DEVICES), so a board
# that is not in mt7620_nand owes nothing. The report says whether each
# listed device is in image/mt7620_nand.mk; what to do with the answer
# is a checklist step in DEVELOPMENT.md.
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

# Composed gates (see the header): BUILD_SUBTARGET set to mt7620. Listed
# with the devices the package is bound to and whether each one has a
# recipe in this subtarget; never a failure by itself.
recipes="target/linux/ramips/image/mt7620_nand.mk"
composed=$(grep -rlE --exclude-dir=.git \
	'^[[:space:]]*BUILD_SUBTARGET[[:space:]]*[:?+]?=[[:space:]]*mt7620[[:space:]]*$' \
	$dirs 2>/dev/null || true)
if [ -n "$composed" ]; then
	echo "note: composed gates on the mt7620 subtarget name (BUILD_SUBTARGET, which a shared"
	echo "  include glues into TARGET_ramips_mt7620). Not a failure: a gate whose devices are"
	echo "  all 'not in mt7620_nand' is device-bound and owes nothing - DEVELOPMENT.md, step 3:"
	for f in $composed; do
		awk -v f="$f" -v recipes="$recipes" '
		/^define / { name = $2; devs = ""; hit = 0 }
		/^[[:space:]]*BUILD_DEVICES[[:space:]]*[:?+]?=/ { devs = $0; sub(/^[^=]*=[[:space:]]*/, "", devs) }
		/^[[:space:]]*BUILD_SUBTARGET[[:space:]]*[:?+]?=[[:space:]]*mt7620[[:space:]]*$/ {
			if (name == "") printf "  %s:%d: BUILD_SUBTARGET mt7620 outside a define block - read it by hand\n", f, NR
			else hit = 1
		}
		/^endef/ {
			if (hit) {
				n = split(devs, d, /[[:space:]]+/); out = ""
				for (i = 1; i <= n; i++) if (d[i] != "") {
					cmd = "grep -q \"^define Device/" d[i] "$\" " recipes
					out = out (out == "" ? "" : ", ") d[i] ": " ((system(cmd) == 0) ? "in" : "not in") " mt7620_nand"
				}
				printf "  %s: %s -> %s\n", f, name, (out == "" ? "no BUILD_DEVICES - read it by hand" : out)
			}
			name = ""; hit = 0
		}' "$f"
	done
fi
exit $status
