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

# sanity: the device must have survived defconfig
grep -q "CONFIG_TARGET_ramips_mt7620_DEVICE_xiaomi_miwifi-r3=y" .config || {
	echo "ERROR: xiaomi_miwifi-r3 profile missing after defconfig"
	exit 1
}

make -j"$(nproc)" download
make -j"$(nproc)" world

mkdir -p /repo/mt7620-nand/out
cp -v bin/targets/ramips/mt7620/*miwifi-r3* /repo/mt7620-nand/out/
cp -v bin/targets/ramips/mt7620/sha256sums /repo/mt7620-nand/out/ 2>/dev/null || true
awk '$1 == "kernel" { print "kernel package: " $3 }' bin/targets/ramips/mt7620/*.manifest | head -n1
echo "DONE - images in mt7620-nand/out/"
