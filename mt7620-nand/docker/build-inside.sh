#!/bin/bash
# Runs INSIDE the builder container. Expects:
#   /repo             this checkout (bind mount; read as a git remote, write: mt7620-nand/out/)
#   /home/build       persistent named volume (source tree + downloads survive runs)
# Env:
#   REF               commit/branch of /repo to build (default: HEAD of /repo)
#
# The build happens in the volume, never on the bind mount: OpenWrt cannot
# build on a case-insensitive filesystem, and the volume keeps dl/ and the
# toolchain between runs. The tree is fetched FROM /repo, so what gets
# built is exactly the local commit - pushed or not.
set -e

REF=${REF:-HEAD}
cd /home/build

if [ ! -d src ]; then
	git clone /repo src
fi
cd src
git fetch /repo "$REF"
git checkout -q --detach FETCH_HEAD
echo "building $(git rev-parse --short HEAD): $(git log -1 --format=%s)"

./scripts/feeds update -a
./scripts/feeds install -a

cp mt7620-nand/config.seed .config
make defconfig

# sanity: the subtarget, ImageBuilder, and key target packages must survive defconfig
for sym in \
	CONFIG_TARGET_ramips_mt7620_nand=y \
	CONFIG_TARGET_MULTI_PROFILE=y \
	CONFIG_ALL_NONSHARED=y \
	CONFIG_ALL_KMODS=y \
	CONFIG_IB=y \
	CONFIG_IB_STANDALONE=y \
	CONFIG_PACKAGE_kmod-rt2800-soc=y; do
	grep -q "^${sym}$" .config || {
		echo "ERROR: $sym missing after defconfig"
		exit 1
	}
done
for p in kmod-mt76x2 uboot-envtools; do
	grep -qE "^CONFIG_PACKAGE_${p}=[ym]$" .config || {
		echo "ERROR: $p missing after defconfig"
		exit 1
	}
done

make -j"$(nproc)" download
make -j"$(nproc)" world

rm -rf /repo/mt7620-nand/out && mkdir -p /repo/mt7620-nand/out
cp -v bin/targets/ramips/mt7620_nand/immortalwrt-imagebuilder-*.tar.* /repo/mt7620-nand/out/
cp -v bin/targets/ramips/mt7620_nand/config.buildinfo /repo/mt7620-nand/out/
cp -v bin/targets/ramips/mt7620_nand/feeds.buildinfo /repo/mt7620-nand/out/
cp -v bin/targets/ramips/mt7620_nand/version.buildinfo /repo/mt7620-nand/out/
(cd /repo/mt7620-nand/out && sha256sum * > sha256sums)
echo "kernel package: $(head -n1 staging_dir/target-*/kernel.version)"
echo "DONE - ImageBuilder in mt7620-nand/out/"
