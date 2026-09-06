#!/bin/sh
# tag-release.sh - cut a release tag for the current HEAD and push it.
#
#   usage: mt7620-nand/scripts/tag-release.sh [-p|--prerelease <reason>]
#
# -p marks the release as a GitHub pre-release: the reason is stored as a
# "Prerelease:" trailer in the tag annotation, and the workflow turns it
# into the --prerelease flag plus a warning at the top of the notes. Use
# it for anything that was not verified on hardware before tagging.
#
# The upstream version is not an argument: it is derived from the tree
# (the nearest upstream release tag below HEAD), because the tree IS the
# pinned upstream version. The script computes the next free <ref>-rN
# release number from the tags already on origin, tags HEAD, and pushes
# the tag. The tag push triggers .github/workflows/release.yml, which
# builds the tagged commit and publishes the GitHub release. Numbering is
# per upstream version and collision-proof: git refuses to push a tag
# that already exists on origin.
set -eu

PRE=""
while [ $# -gt 0 ]; do
	case "$1" in
	-p|--prerelease)
		[ -n "${2:-}" ] || { echo "ERROR: $1 needs a reason" >&2; exit 1; }
		PRE=$2; shift 2 ;;
	*)
		echo "usage: $0 [-p|--prerelease <reason>]" >&2; exit 1 ;;
	esac
done

[ -z "$(git status --porcelain)" ] || {
	echo "ERROR: working tree not clean - commit or stash first" >&2
	exit 1
}

git fetch -q origin

# A release must be cut from a commit that is on a published branch: the
# workflow builds the tagged commit, and a tag on an unpushed commit would
# release code that no branch ever saw.
[ -n "$(git branch -r --contains HEAD 2>/dev/null | grep '^ *origin/')" ] || {
	echo "ERROR: HEAD is not on any origin branch - push it first" >&2
	exit 1
}

# Nearest upstream release tag (v25.12.1, ...) below HEAD; our own release
# tags (v25.12.1-rN) are excluded so a previously tagged HEAD still
# resolves to its upstream base.
REF=$(git describe --tags --abbrev=0 --match 'v[0-9]*' --exclude 'v*-r[0-9]*' HEAD) || {
	echo "ERROR: no upstream release tag found below HEAD (fetch tags?)" >&2
	exit 1
}

# Highest existing rN for this upstream version (max + 1, so a deleted
# release can never cause a reused number). The awk prefix test avoids
# treating dots in the ref as regex; the numeric test drops the ^{}
# dereference lines git ls-remote prints for annotated tags.
last=$(git ls-remote --tags origin "refs/tags/${REF}-r*" \
	| awk -v p="refs/tags/${REF}-r" '
		index($2, p) == 1 {
			n = substr($2, length(p) + 1)
			if (n ~ /^[0-9]+$/) print n
		}' \
	| sort -n | tail -n1)
TAG="${REF}-r$(( ${last:-0} + 1 ))"

msg="ImmortalWrt $REF for Mi Router 3, port build $TAG"
[ -z "$PRE" ] || msg="$msg

Prerelease: $PRE"
git tag -a "$TAG" -m "$msg"
git push origin "$TAG"

echo "Pushed $TAG${PRE:+ (pre-release)} - the release workflow is building it now."
