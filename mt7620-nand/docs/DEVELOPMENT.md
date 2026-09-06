# Development guide

How this repository is structured, and how to build, test, release,
and follow upstream. What the port changes and why:
[PORT-NOTES.md](PORT-NOTES.md). How the conclusions were reached
(dead ends included): [RESEARCH-LOG.md](RESEARCH-LOG.md).

## How the repository is structured

This is a fork of ImmortalWrt. One branch per upstream release line
(`git branch -r` lists them); the first, created 2026-09-06, is
`25.12`, which is the upstream tag `v25.12.1` plus a short commit
series:

```text
v25.12.1 (upstream)
  ├─ ramips: add mt7620-nand driver for NAND flash          ┐
  ├─ ramips: add Xiaomi Mi Router R3 support                │ the port
  ├─ base-files: nand: support writing the kernel to a …    │ (PORT-NOTES.md)
  ├─ ramips: ralink_nand: report corrected bitflips so …    │
  ├─ imagebuilder: list remote userland feeds in …          ┘
  └─ mt7620-nand: project files (this doc, seed, CI, …)     project folder
```

`git log v25.12.1..25.12` shows exactly what the port is; GitHub's
compare view between the upstream tag and the branch is the
reviewable form. There is no patch directory and no installer: the
tree at any commit *is* the pinned combination of ImmortalWrt code
and X-Wrt-derived code, so the same commit builds the same firmware
everywhere.

Everything that is *about* the port rather than part of it lives in
one folder, `mt7620-nand/`, plus two files GitHub insists on placing
elsewhere:

| | |
|---|---|
| `mt7620-nand/config.seed` | build seed (target + device + LuCI + kmod/IB/ccache options, each explained inline) |
| `mt7620-nand/scripts/tag-release.sh` | cuts a release: computes the next `<upstream>-rN`, tags HEAD, pushes |
| `mt7620-nand/scripts/check-xwrt-drift.sh` | reports whether x-wrt master's versions of the four ported files changed |
| `mt7620-nand/docker/`, `mt7620-nand/build.ps1` | local containerized build of the current checkout |
| `mt7620-nand/docs/` | this documentation; `mt7620-nand/docs/boot-logs/` holds archived serial logs |
| `mt7620-nand/.gitignore` | ignores `PRIVATE-NOTES.md` and `out/` inside the folder |
| `.github/workflows/release.yml` | CI: tag push → build + publish release; manual dispatch → test build (artifacts only). GitHub only finds workflows here. |
| `README.md` | replaces upstream's, because GitHub renders the root README (expect a trivial "keep ours" conflict on rebase) |

Everything else in the tree is ImmortalWrt. So the tree differs from
upstream by the port itself plus exactly three things: the folder, the
workflow file, and the README.

### Submitting the port upstream

An upstream submission is the tree minus those three things, as one
commit on a fresh branch from the upstream tag:

```bash
git checkout -b for-upstream v25.12.1
git diff v25.12.1 25.12 -- . ':!mt7620-nand' ':!.github/workflows/release.yml' ':!README.md' | git apply --index
git commit    # attribute the driver, DTS and device support to Chen Minqiang (x-wrt); see PROVENANCE.md
```

What upstream would additionally ask for is content, not layout: a
separate `mt7620-nand` subtarget instead of `FEATURES += nand` on the
shared mt7620 one ([PORT-NOTES.md](PORT-NOTES.md#upstreaming-outlook)).

## Building

**Any Linux host** (the same steps CI runs):

```bash
git clone -b 25.12 https://github.com/VinhNgT/immortalwrt-mt7620-nand.git
cd immortalwrt-mt7620-nand
./scripts/feeds update -a && ./scripts/feeds install -a
cp mt7620-nand/config.seed .config && make defconfig
make -j"$(nproc)" download && make -j"$(nproc)"
```

Images land in `bin/targets/ramips/mt7620/`.

**Docker** (Windows host): `.\mt7620-nand\build.ps1` — builds the
`iwrt-builder` image, fetches the *current local commit* of this
checkout into a named volume (`iwrt-src`, so re-runs are fast), and
drops images in `mt7620-nand\out\`. Add `-Shell` for an interactive shell in the build
container instead. The build runs inside the volume, never on the
Windows bind mount (OpenWrt cannot build on a case-insensitive
filesystem).

## Test builds in CI

Dispatch the release workflow manually ("Run workflow" on the Actions
page), picking the branch or commit to build — there are no other
inputs. It runs the full pipeline and uploads the images as workflow
**artifacts**, publishing nothing. Use this to shake out a change
before cutting a release. Each run's summary shows the kernel package
version; it changes only when kernel-side inputs change, so it is a
quick check that a change did what it was meant to.

## Cutting a release

```bash
sh mt7620-nand/scripts/tag-release.sh
```

Add `-p "<reason>"` to publish a **pre-release** (for example a build
that could not be RAM-booted first): the reason is stored in the tag
annotation and the workflow marks the GitHub release as a pre-release
with a warning on top of its notes.

The script derives the upstream version from the nearest upstream
tag below HEAD (`git describe`), refuses a dirty tree or a HEAD that
is not on an `origin` branch, computes the next free
`<version>-rN` from origin's tags (max + 1, so deleted releases never
cause number reuse), tags HEAD, and pushes the tag. The tag push
triggers `.github/workflows/release.yml`, which checks that the tag's
version prefix matches the tree's upstream base, builds, and publishes
the GitHub release: all image formats, the manifest, `sha256sums`, and
the build's ImageBuilder, with notes recording the upstream base, the
port commit, the x-wrt provenance, and the kernel package version.

Rules:

- **Releases are immutable.** Every build has a unique kernel
  vermagic, so a release's ImageBuilder must stay downloadable
  unchanged for as long as anyone runs that release's image. Never
  edit a published release's assets; any rebuild is the next `-rN`.
- **Release only what was RAM-booted.** Before tagging, RAM-boot the
  initramfs from the test build of the same commit
  ([RECOVERY.md](RECOVERY.md)) and note it in the release. If that is
  not possible, tag with `-p` so the release is clearly marked.
- **Tags keep commits alive.** The branch is rebased when upstream
  moves (below), which orphans old commits; a release tag is what
  keeps a released tree fetchable forever. Never build a release from
  an untagged commit, and never delete a release tag.
- **Failure recovery:** if the build fails, fix and re-run the same
  workflow run — the tag stays valid. If publishing half-succeeded,
  delete the incomplete release (not the tag) and re-run.

## CI internals

The authoritative documentation is the comments in
[release.yml](../../.github/workflows/release.yml) itself; the shape:

- **Checkout** is blobless with full history, so `git describe` can
  find the upstream base tag without downloading every blob.
- **Caches**: `dl/` (keyed on the upstream base; release tarballs are
  frozen), toolchain + host trees (keyed on the toolchain sources and
  `config.seed` — build options enter every package's configure
  fingerprint, so restored trees must match the config or make
  re-configures on dirty state and fails), the feeds checkout (feed
  commits are pinned per release), and ccache (saved even on failure
  so retries are cheap). **Any textual change to `config.seed`
  invalidates the toolchain cache** — one ~40 min rebuild, then
  cached again.
- **Guards**: after `make defconfig`, the workflow greps the expanded
  `.config` for load-bearing symbols (`CCACHE`, `ALL_KMODS`, `IB`) —
  defconfig silently drops symbols whose Kconfig prompt is hidden,
  and a silent drop should fail the run in minute two, not waste a
  quiet hour.
- **Failure diagnostics**: `CONFIG_BUILD_LOG=y` writes per-package
  logs, uploaded as a `build-logs` artifact when a run fails.

## Following upstream

**ImmortalWrt point release** (expect one every one to three months;
the 24.10 line had six between April 2025 and April 2026):

```bash
git remote add upstream https://github.com/immortalwrt/immortalwrt.git   # once
git fetch upstream --tags
git checkout 25.12
git rebase v25.12.2            # resolve conflicts, if any, commit by commit
```

Conflicts can only occur in the handful of upstream files the port
edits (listed in [PORT-NOTES.md](PORT-NOTES.md)) and in `README.md`,
where the answer is always "keep ours". Then push a test build,
RAM-boot it, and force-push the branch with `--force-with-lease`.
Old release tags keep the previous trees reachable. Update the
"Status" line in `README.md` and the base tag mentioned in this file.
Keep project-file changes (anything under `mt7620-nand/`) in their
own commits, separate from port changes.

**Kernel bump** (a new upstream line, e.g. `26.x` on a newer kernel):
create a new branch from that tag, cherry-pick the port commits, and
move `patches-<kv>/0038-…` and the `config-<kv>` hunks to the new
kernel version's directory and file. The driver carries
`LINUX_VERSION_CODE` guards; a kernel bump is where they get
exercised, so RAM-boot before anything else.

**X-Wrt sync** — x-wrt is never cloned, and changes are ported by
hand. Run

```bash
sh mt7620-nand/scripts/check-xwrt-drift.sh
```

to download the current x-wrt versions of the four ported files and
compare them against the blob hashes in
[PROVENANCE.md](PROVENANCE.md). If something changed, the script
prints a diff against the tree; port what is relevant as a new
commit, re-apply the ECC-report change if the driver was touched,
and update PROVENANCE.md with the new HEAD sha and hashes. x-wrt
tracks OpenWrt master (kernel 6.18 as of 2026-09), so a cherry-pick
would not apply cleanly onto a release branch anyway — hand-porting
is the honest form.

## Validating changes on hardware

The safety doctrine, in order:

1. Build → **RAM-boot the initramfs image first** (TFTP, zero flash
   writes — procedure in [RECOVERY.md](RECOVERY.md)); verify what the
   change was supposed to change.
2. Only then flash via sysupgrade.
3. Archive noteworthy boot logs under `mt7620-nand/docs/boot-logs/` — **redact
   device identifiers first** (MACs, IPs beyond the router's own
   192.168.1.1, unique IDs); the existing archived log shows the
   masking convention.

Device-private data (serial numbers, backup checksums, local paths)
never goes into tracked files — it belongs in the git-ignored
`mt7620-nand/PRIVATE-NOTES.md`.

## Documentation policy

- `README.md` + `mt7620-nand/docs/GUIDE.md` + `mt7620-nand/docs/RECOVERY.md` are for end
  users: instructions, use cases, quirks — no build-system internals.
- `mt7620-nand/docs/DEVELOPMENT.md` (this file), `mt7620-nand/docs/PORT-NOTES.md`,
  `mt7620-nand/docs/PROVENANCE.md` and `mt7620-nand/docs/RESEARCH-LOG.md` are for developers.
- Docs state settled facts and must be understandable with zero
  project context. The step-by-step/trial-and-error record is kept —
  deliberately, to avoid repeating bad judgments — but only in
  `RESEARCH-LOG.md`.
