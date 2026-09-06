# Build this checkout for the Xiaomi Mi Router 3 in Docker.
# The source tree + downloads live in a named volume (iwrt-src) so re-runs
# are fast; the tree is fetched from this checkout, so the build is exactly
# the local commit. Artifacts land in .\out\ next to this script.
#
# Usage:  .\mt7620-nand\build.ps1                (build HEAD)
#         .\mt7620-nand\build.ps1 -Ref 25.12     (build a branch/commit of this checkout)
#         .\mt7620-nand\build.ps1 -Shell         (drop into a shell instead)
param(
    [string]$Ref = "HEAD",
    [switch]$Shell
)

$ErrorActionPreference = "Stop"
$repo = (Resolve-Path "$PSScriptRoot\..").Path   # repository root

docker build -t iwrt-builder "$repo\mt7620-nand\docker"
if ($LASTEXITCODE -ne 0) { exit 1 }

docker volume create iwrt-src | Out-Null

if ($Shell) {
    docker run -it --rm -v iwrt-src:/home/build -v "${repo}:/repo" iwrt-builder bash
} else {
    docker run --rm -e REF=$Ref -v iwrt-src:/home/build -v "${repo}:/repo" `
        iwrt-builder bash /repo/mt7620-nand/docker/build-inside.sh
}
