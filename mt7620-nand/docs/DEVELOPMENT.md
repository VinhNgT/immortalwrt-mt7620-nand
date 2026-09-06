# Development guide

What this fork is for, how it is structured, how to build, test and
release it, and the exact procedures for following ImmortalWrt and
x-wrt. What the port changes and why: [PORT-NOTES.md](PORT-NOTES.md).
How the conclusions were reached, dead ends included:
[RESEARCH-LOG.md](RESEARCH-LOG.md).

## Scope

The fork exists for exactly these things; a change that serves none
of them does not belong here:

1. **mt7620-nand support** as the `mt7620_nand` subtarget of `ramips`
   — only the Xiaomi Mi Router R3 for now.
2. **Fix the NAND driver's ECC reporting** so UBI can scrub bitflips.
3. **A local-only-kmod ImageBuilder**: every kernel module built and
   bundled with each release, userland packages from the official
   feeds.
4. **A CI release workflow**: a tag push builds and publishes a
   release; a manual run is a test build.
5. **Documentation**: research notes, user guides and this project's
   own README, kept under `mt7620-nand/`.
6. **A local containerized build** for a Windows host
   (`mt7620-nand/build.ps1`).
7. **Tracking x-wrt as the driver's source**: provenance by content
   hash and a drift check.
8. **LuCI in the images**, as in ImmortalWrt's official releases.
9. **Device-private data kept out of the repository**
   (`mt7620-nand/PRIVATE-NOTES.md` is git-ignored).

Two rules follow from this being a fork of ImmortalWrt, not of x-wrt:

- **Take the minimum from x-wrt.** x-wrt is where the R3 is officially
  supported and is the source of the driver, the device tree and the
  device support — but only what the R3 needs is taken, piece by
  piece, each piece accounted for in [PORT-NOTES.md](PORT-NOTES.md).
  x-wrt carries a large stack of unrelated changes on top of OpenWrt;
  bringing it over wholesale would make this tree incoherent.
- **Follow ImmortalWrt's conventions, not x-wrt's.** Where the two
  disagree — where a file lives, how a subtarget is shaped, how
  sysupgrade writes a partition — the ImmortalWrt/OpenWrt way wins,
  even when that means diverging from x-wrt's text. The `mt7620_nand`
  subtarget and the second-kernel-slot write in `platform.sh` are both
  results of this rule.

A third rule follows from the subtarget: **`mt7620_nand` is mt7620
plus NAND and nothing less.** Its kernel config is mt7620's plus one
fragment, its target.mk differs from mt7620's only by the nand feature
and its name, and every dependency gate that names the mt7620
subtarget names `mt7620_nand` too. In ramips a subtarget name means an
SoC, so a gate that forgets the second name silently makes a package
unavailable there, and defconfig drops an unsatisfiable default
package without a word, so nothing else would notice. How this was
learned is in [RESEARCH-LOG.md](RESEARCH-LOG.md), under *Corrections*.

## How the repository is structured

This is a fork of ImmortalWrt. One branch per upstream release line
(`git branch -r` lists them); the first, created 2026-09-06, is
`25.12`, which is the upstream tag `v25.12.1` plus the port. The
series as first assembled, and the shape later commits build on:

```text
v25.12.1 (upstream)
  ├─ ramips: add mt7620-nand driver for NAND flash              ┐
  ├─ ramips: add mt7620_nand subtarget                          │ the port
  ├─ ramips: add support for Xiaomi Mi Router R3                │ (PORT-NOTES.md)
  ├─ ramips: ralink_nand: report corrected bitflips so …        │
  ├─ imagebuilder: list remote userland feeds in …              ┘
  ├─ mt7620-nand: add the subtarget kernel-config fragment …    ┐
  ├─ mt7620-nand: add build seed, release workflow and …        │
  ├─ mt7620-nand: add containerized local build                 │ project folder
  ├─ mt7620-nand: record x-wrt provenance and add a drift check │
  └─ mt7620-nand: add documentation and replace the README      ┘
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
| `mt7620-nand/scripts/check-xwrt-drift.sh` | reports whether x-wrt master's versions of the four whole files taken from it changed; `--hunks` prints x-wrt's R3 lines from its shared files |
| `mt7620-nand/scripts/sync-subtarget-config.sh`, `mt7620-nand/subtarget-kconfig.fragment` | regenerates (or, with `--check`, verifies) the mt7620_nand kernel config as mt7620's config plus the fragment, and lists any dependency gate on the mt7620 subtarget name that lacks `mt7620_nand` |
| `mt7620-nand/docker/`, `mt7620-nand/build.ps1` | local containerized build of the current checkout |
| `mt7620-nand/docs/` | this documentation; `mt7620-nand/docs/boot-logs/` holds archived serial logs |
| `mt7620-nand/.gitignore` | ignores `PRIVATE-NOTES.md` and `out/` inside the folder |
| `.github/workflows/release.yml` | CI: tag push → build + publish release; manual dispatch → test build (artifacts only). GitHub only finds workflows here. |
| `README.md` | replaces upstream's, because GitHub renders the root README (expect a trivial "keep ours" conflict on rebase) |

Everything else in the tree is ImmortalWrt. So the tree differs from
upstream by the port itself plus exactly three things: the folder, the
workflow file, and the README.

### Commits and history

Day-to-day changes are ordinary commits on top of the series; the
diagram above is the port as first assembled, not a shape every later
change has to be folded into. History is rewritten only when there is
a reason to: an upstream rebase (below) rewrites it by nature, and a
deliberate cleanup of the series is a decision taken each time, not a
standing rule.

When history is rewritten: keep the previous branch on origin as
`backup/<branch>-<reason>-<date>` until the new one has been built and
booted (release tags keep released trees reachable regardless); when
the rewrite is meant to be content-neutral, check that the tree before
and after is identical (`git diff <old tip> HEAD` is empty); then push
with `--force-with-lease`. To fold a change into the commit that
introduced what it changes, commit it with the subject
`fixup! <that commit's subject>` (or `amend!`, with the complete new
message after a blank line, to replace the message too) and run
`git -c sequence.editor=true rebase -i --autosquash <upstream tag>`.

### Submitting upstream

The only thing that would be submitted is the mt7620-nand support
itself: the driver with the ECC fix, the `mt7620_nand` subtarget, and
the one device. Nothing else in this tree is part of that: not the
ImageBuilder feeds change (an ImmortalWrt build-system matter of its
own), not the project folder, the workflow or the README.

The submission is the port commits of the series, re-cut the way a
reviewer expects, on a scratch branch from the upstream tag:

```bash
git checkout -b for-upstream v25.12.1
git log --reverse --format='%h %s' v25.12.1..25.12 | grep ' ramips: '   # the port commits, in order
git cherry-pick <those hashes>
git rebase -i v25.12.1     # squash the ECC-report commit into the driver commit, and any
                           # later "ramips:" sync commits into the commit that owns their files
```

That leaves three commits, each building on its own: the driver, with
the ECC fix already in it because a new driver is reviewed in its
final form; the subtarget; and the R3. Keep the attribution: the
driver, the DTS and the device support are Chen Minqiang's (x-wrt),
recorded in [PROVENANCE.md](PROVENANCE.md); the ECC fix, the subtarget
shape and the second-kernel-slot write are this project's.

ImmortalWrt is the natural first target: it carried this driver and
device on its 18.06 line until 2023, and the port already follows its
conventions. What OpenWrt asked for in 2022 beyond the subtarget is
content, not layout: a driver rewritten on the rawnand framework
([PORT-NOTES.md](PORT-NOTES.md#upstreaming-outlook)).

## Building

**Any Linux host** (the same steps CI runs):

```bash
git clone -b 25.12 https://github.com/VinhNgT/immortalwrt-mt7620-nand.git
cd immortalwrt-mt7620-nand
./scripts/feeds update -a && ./scripts/feeds install -a
cp mt7620-nand/config.seed .config && make defconfig
make -j"$(nproc)" download && make -j"$(nproc)"
```

Images land in `bin/targets/ramips/mt7620_nand/`.

**Docker** (Windows host): `.\mt7620-nand\build.ps1` — builds the
`iwrt-builder` image, fetches the *current local commit* of this
checkout into a named volume (`iwrt-src`, so re-runs are fast), and
drops images in `mt7620-nand\out\`. Add `-Shell` for an interactive
shell in the build container instead. The build runs inside the
volume, never on the Windows bind mount (OpenWrt cannot build on a
case-insensitive filesystem). It applies the same post-defconfig
guards as CI.

## Test builds in CI

Dispatch the release workflow manually ("Run workflow" on the Actions
page), picking the branch or commit to build — there are no other
inputs. It runs the full pipeline and uploads the images as workflow
**artifacts**, publishing nothing. Use this to shake out a change
before cutting a release. Each run's summary shows the kernel package
version; it changes only when kernel-side inputs change, so it is a
quick check that a change did what it was meant to. The artifact's
`.manifest` lists every package in the image; `kmod-rt2800-soc` and
`kmod-mt76x2` must be in it.

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
- **Subtarget check**: right after the feeds are installed,
  `sync-subtarget-config.sh --check` verifies the mt7620_nand kernel
  config and scans the tree and the feeds for dependency gates that
  name mt7620 without `mt7620_nand`. It runs before the toolchain so
  a drift fails in minutes.
- **Guards**: after `make defconfig`, the workflow greps the expanded
  `.config` for the device profile, `CCACHE`, `ALL_KMODS`, `IB`, and
  both radio kmods — defconfig silently drops symbols whose Kconfig
  prompt is hidden and default packages whose dependencies are
  unsatisfied, and a silent drop should fail the run in minute two,
  not waste a quiet hour or ship an image without WiFi.
- **Failure diagnostics**: `CONFIG_BUILD_LOG=y` writes per-package
  logs, uploaded as a `build-logs` artifact when a run fails.

## What is checked by a script and what is checked by you

| What can drift | Checked by | When |
|---|---|---|
| mt7620_nand kernel config vs mt7620's plus the fragment | `sync-subtarget-config.sh` | every CI build; by hand after a rebase |
| dependency gates on the mt7620 subtarget name | `sync-subtarget-config.sh` | same |
| default packages surviving defconfig (profile, both radios) | `release.yml`, `build-inside.sh` | every build |
| the four whole files taken from x-wrt | `check-xwrt-drift.sh` | by hand, per the x-wrt procedure |
| x-wrt's R3 hunks in its shared files | you, with `check-xwrt-drift.sh --hunks` | same |
| mt7620's target.mk | you, one diff | after every rebase |
| mt7620's base-files gaining behaviour that is not a per-board list | you, one diff | after every rebase |
| version and tag mentions in README and this file | you | after every rebase |

The manual rows are manual on purpose: each needs a judgment a script
cannot make, and a script that pretends otherwise would only add a
false all-clear. The procedures below say exactly where each check
goes.

## Following ImmortalWrt

### A new point release on the same line

Expect one every one to three months; the 24.10 line had six between
April 2025 and April 2026. Example: `v25.12.1` → `v25.12.2`.

1. Fetch and back up:

   ```bash
   git remote add upstream https://github.com/immortalwrt/immortalwrt.git   # once
   git fetch upstream --tags
   git checkout 25.12
   git branch backup/25.12-pre-v25.12.2-$(date +%Y%m%d) && git push origin backup/25.12-pre-v25.12.2-$(date +%Y%m%d)
   ```

2. Rebase the series: `git rebase v25.12.2`, resolving conflicts
   commit by commit and keeping each commit's scope. Conflicts can
   only occur where the port edits upstream files: the uboot-envtools
   board list, `ralink.mk`, ramips' `modules.mk`, the lzma loader's
   `src/Makefile`, ramips' `Makefile`, the mt7620 and mt76x8 kernel
   configs, `target/imagebuilder/Makefile`, and `README.md` (always
   "keep ours").

3. Run the subtarget sync: `sh mt7620-nand/scripts/sync-subtarget-config.sh`.
   It regenerates `target/linux/ramips/mt7620_nand/config-<kv>` from
   mt7620's new config and fails if any gate on the mt7620 subtarget
   name lacks `mt7620_nand`; add the name in the file it points at.
   Commit the regenerated config and any gate edits; the rebase is
   already rewriting history, so folding them into the subtarget
   commit is reasonable but not required.

4. The manual checks, each one command:

   - `diff target/linux/ramips/mt7620/target.mk target/linux/ramips/mt7620_nand/target.mk`
     — only the `SUBTARGET`, `BOARDNAME`, `FEATURES` and description
     lines may differ. Port anything else (a changed default package,
     CPU type) into the subtarget's copy.
   - `git diff v25.12.1 v25.12.2 -- target/linux/ramips/mt7620/base-files`
     — anything added that is **not** a per-board case list (a hotplug
     script, a uci-defaults step, a generic function) applies to every
     MT7620 board and needs a counterpart under
     `target/linux/ramips/mt7620_nand/base-files/`. Per-board entries
     for other boards need nothing.
   - `grep -rn 'v25\.12\.1' README.md mt7620-nand/docs/DEVELOPMENT.md mt7620-nand/docs/PORT-NOTES.md`
     — update the mentions that describe the current state (README's
     status and branch description, the tags in this file's commands,
     PORT-NOTES' kernel/target choice). Historical mentions in
     RESEARCH-LOG.md stay.

5. Push a test build, check its Configure step passed the guards and
   its manifest has both radios, then RAM-boot the initramfs
   ([RECOVERY.md](RECOVERY.md)).

6. `git push --force-with-lease origin 25.12`, then cut the release
   with `tag-release.sh`. Delete the backup branch once the release is
   out.

Keep project-file changes (anything under `mt7620-nand/`) in their
own commits, separate from port changes, as the series already does.

### A new release line, usually with a new kernel

Example: a `26.x` line on kernel 6.18. The old line's branch stays as
it is; the new line gets its own branch, named after the line.

1. `git fetch upstream --tags`, then
   `git checkout -b 26.x v26.x.0`.

2. Bring the series over: `git cherry-pick v25.12.1..25.12`. Resolve
   conflicts as in the point-release procedure. Two conflicts are
   specific to a kernel bump and land in the driver and subtarget
   commits:
   - the Kconfig hook patch and the mt7620/mt76x8 "not set" lines
     target `patches-<old kv>/` and `config-<old kv>`; move them to the
     new kernel's directory and files (`git mv` the patch; re-add the
     two lines to the new configs);
   - `target/linux/ramips/mt7620_nand/config-<old kv>` must be
     replaced: delete it and run
     `sh mt7620-nand/scripts/sync-subtarget-config.sh` to generate
     `config-<new kv>` from mt7620's.

3. Check the fragment survived the kernel: the merge only overlays
   symbols, so a symbol the new kernel renamed would be silently
   dropped at build time. After the first build,
   `grep -E 'MTD_NAND_MT7620|MTD_UBI=|UBIFS_FS=' build_dir/target-*/linux-ramips_mt7620_nand/linux-*/.config`
   must show them all `=y`; if not, fix `subtarget-kconfig.fragment`.

4. Check x-wrt for the new kernel first:
   `sh mt7620-nand/scripts/check-xwrt-drift.sh` looks for the Kconfig
   hook in x-wrt's `patches-<new kv>/` and reports the driver's
   current state. The driver carries `LINUX_VERSION_CODE` guards; a
   kernel bump is where they get exercised. Kernel 6.18 was built and
   booted in August 2026; anything newer starts from that.

5. Run the manual checks from the point-release procedure (target.mk,
   base-files, version mentions — here the whole `v25.12.1` → new-tag
   set, plus PROVENANCE.md's patch-path row).

6. Test build, then **RAM-boot before anything else** — a kernel bump
   is the one change where the driver itself is in question. Then push
   the branch and cut the release. Nothing in `config.seed` or the
   workflow needs changing: the target symbols are the same and the
   workflow derives the upstream base from the tree.

## Syncing from x-wrt

x-wrt is never cloned, and changes are ported by hand. Do this whenever
the drift check is run — at least at every upstream rebase, and
whenever x-wrt is known to have touched the driver.

1. `sh mt7620-nand/scripts/check-xwrt-drift.sh`. It downloads x-wrt
   master's current copies of the four whole files (driver, header,
   DTS, Kconfig hook), compares their blob hashes against
   [PROVENANCE.md](PROVENANCE.md), and prints a diff against this tree
   for anything changed. A file it cannot fetch is reported as drift,
   not as unchanged; find where x-wrt moved it and pass the new path
   on. Exit 0 with "No drift" means nothing to do for these four.

2. For each changed file, read the diff and port only what the R3
   needs, as a new commit with x-wrt's attribution in the message and
   a note of what was left out and why. If the driver was touched,
   port the change on top of our copy, which carries the ECC-report
   fix; the drift script's diff shows that fix as `-` lines, which are
   ours to keep.

3. `sh mt7620-nand/scripts/check-xwrt-drift.sh --hunks`. This prints
   x-wrt's current R3-related lines from its `image/mt7620.mk`,
   mt7620's `02_network` and `platform.sh`, and the uboot-envtools
   board list. Compare them by eye with ours in
   `target/linux/ramips/image/mt7620_nand.mk`,
   `target/linux/ramips/mt7620_nand/base-files/` and the uboot-envtools
   line. The recipe, the network cases and the envtools line are meant
   to stay byte-identical; `platform.sh` differs on purpose
   ([PORT-NOTES.md](PORT-NOTES.md#what-differs-from-x-wrt--the-audit))
   and takes only changes to the bootloader detection.

4. Update PROVENANCE.md: the x-wrt HEAD sha and date the sync was
   taken from, and the blob hashes of the files as taken (`git
   hash-object` of x-wrt's copy, before the ECC-report change).

5. Test build; RAM-boot if the driver or the DTS changed; release.

x-wrt tracks OpenWrt master (kernel 6.18 as of 2026-09), so a
cherry-pick from it would not apply cleanly onto a release branch
anyway — hand-porting is the honest form.

## Validating changes on hardware

The safety doctrine, in order:

1. Build → **RAM-boot the initramfs image first** (TFTP, zero flash
   writes — procedure in [RECOVERY.md](RECOVERY.md)); verify what the
   change was supposed to change.
2. Only then flash via sysupgrade.
3. Archive noteworthy boot logs under `mt7620-nand/docs/boot-logs/` —
   **redact device identifiers first** (MACs, IPs beyond the router's
   own 192.168.1.1, unique IDs); the existing archived log shows the
   masking convention.

Device-private data (serial numbers, backup checksums, local paths)
never goes into tracked files — it belongs in the git-ignored
`mt7620-nand/PRIVATE-NOTES.md`.

## Documentation policy

- `README.md` + `mt7620-nand/docs/GUIDE.md` + `mt7620-nand/docs/RECOVERY.md`
  are for end users: instructions, use cases, quirks — no build-system
  internals.
- `mt7620-nand/docs/DEVELOPMENT.md` (this file),
  `mt7620-nand/docs/PORT-NOTES.md`, `mt7620-nand/docs/PROVENANCE.md`
  and `mt7620-nand/docs/RESEARCH-LOG.md` are for developers.
- Docs state settled facts and must be understandable with zero
  project context. The step-by-step/trial-and-error record is kept —
  deliberately, to avoid repeating bad judgments — but only in
  `RESEARCH-LOG.md`.
- Every procedure in this file is complete as written: if a step
  needs knowledge that is only in someone's head, the fix is to write
  the step down, not to remember harder.
