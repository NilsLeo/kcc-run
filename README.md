# kcc-run

Run **any [KCC](https://github.com/ciromattia/kcc) fork/branch's CLI** against a
file, in a throwaway container. The KCC `owner/repo:ref` is a **runtime
argument**, so one image reproduces and A/B-tests conversion bugs across
branches without rebuilding.

```
docker run --rm -v "$PWD:/work" ghcr.io/nilsleo/kcc-run  <owner/repo[:ref]>  <kcc-c2e.py args...>
```

## Quick start

The `--platform linux/amd64` flag is a no-op on Intel/AMD hosts and makes the
image run under emulation on Apple Silicon (see [Apple Silicon](#apple-silicon-arm-macs)).

```bash
docker pull --platform linux/amd64 ghcr.io/nilsleo/kcc-run:latest

# upstream master (default branch if you omit :ref)
docker run --platform linux/amd64 --rm -v "$PWD:/work" ghcr.io/nilsleo/kcc-run ciromattia/kcc:master -p KV -f EPUB -o out mybook.cbz

# a fork's feature branch — same image, no rebuild
docker run --platform linux/amd64 --rm -v "$PWD:/work" ghcr.io/nilsleo/kcc-run NilsLeo/kcc:up/image-resilience -p KV -f EPUB -o out mybook.cbz

# MOBI works too (kindlegen is bundled)
docker run --platform linux/amd64 --rm -v "$PWD:/work" ghcr.io/nilsleo/kcc-run ciromattia/kcc:master -p KV -f MOBI -o out mybook.cbz
```

A shell shortcut so it reads exactly like `repo:ref  cli args`:

```bash
kcc() { docker run --platform linux/amd64 --rm -v "$PWD:/work" -w /work ghcr.io/nilsleo/kcc-run "$@"; }

kcc ciromattia/kcc:master -p KV -f EPUB -o out mybook.cbz
kcc NilsLeo/kcc -p KV -f EPUB -o out mybook.pdf   # no :ref → master
```

## Triage workflow (problem archives from prod)

Convention: problem files land in `../files/triage/` (usually named
`Title_<jobid>.<ext>`); disposition dirs `DONE` / `CANT DO` / `WONT Do` sit next
to it; run artifacts (logs, extracted output, notes) go to
`../kcc-feature-results/triage-runs/`. "Apply the triage workflow to the triage
dir" means, per file:

1. **Inspect the archive before running anything.** Magic bytes (`file`,
   `xxd | head`), listing (`bsdtar -tvf`, `zipinfo`). This alone caught: zero-byte
   image placeholders (Kousai), HTML error documents instead of images
   (MangaPlus/CRUELTY), truncated RAR central directory (HxH). Note counts:
   how many entries are real images vs junk.
2. **Reproduce with prod-like args** and capture full stderr:
   `kcc NilsLeo/kcc -p <profile> -f EPUB -o out <file>` — map the job's device
   to the KCC profile the worker would use (e.g. KoLC; see the "KCC Command"
   column in the Grafana Jobs table for the exact flags of the failing job).
   Work on a **copy**; run in a scratch dir.
3. **Classify the failure.** Match stderr against the worker's `ERR:*` mapping
   (`apps/worker/src/conversion/kcc-process.service.ts` in mangaconverter-saas).
   If it lands in `ERR:unknown`, that's a finding: propose a new stderr→class
   mapping (NIL-636 pattern) so users get a real message.
4. **Damaged archives: A/B the salvage path.** The fork's master carries the
   bsdtar salvage patch (NIL-624). Run upstream vs fork with identical args:
   `kcc ciromattia/kcc:master …` vs `kcc NilsLeo/kcc …`. Fork extracting
   most pages while upstream dies = salvageable; report page counts.
5. **Fix if warranted** via the fork-PR flow below; rebuild/redeploy the worker
   image so prod picks it up (worker Dockerfile clones the fork).
6. **Record and file.** Per-file verdict into
   `../kcc-feature-results/triage-runs/`: root cause, ERR class (current vs
   proposed), salvage result, user-facing message quality. Move the file to
   `DONE` / `CANT DO` / `WONT Do`, and track code changes as Linear tickets
   (team NilsWork, project MangaConverter).

## Fork development workflow

In the local `kcc-fork` checkout, the `upstream` remote points to
`ciromattia/kcc`, and the local `upstream-base` branch tracks
`upstream/master`. Keep `upstream-base` synchronized with the actual upstream
branch and use it—not the fork's customized `master`—as the base for feature
branches intended for upstream pull requests:

```bash
git fetch upstream
git switch upstream-base
git pull --ff-only
git switch -c up/my-feature
```

After committing the feature, push it to the fork and open the pull request
against `ciromattia/kcc:master`:

```bash
git push -u origin up/my-feature
gh pr create --repo ciromattia/kcc --base master --head NilsLeo:up/my-feature
```

### Minimal PR description

````markdown
Fixes #<issue>

## Problem
<What fails and the relevant error.>

## Fix
<What changed and why.>

## Reproduce / test
Fixture: <Google Drive link>
Filename: <fixture filename as uploaded/shared>
Filepath: <local path under /work that the commands below reference>

```bash
# Upstream: <expected failure>
kcc ciromattia/kcc:master <args> book.cbz

# This branch: <expected success>
kcc NilsLeo/kcc:<branch> <args> book.cbz
```
````

## How it works

- The image bakes KCC's Python deps (`PyMuPDF`, `numpy`,
  `requirements-docker.txt` from upstream master) once at build time.
- At **run** time, `entry.sh` parses `owner/repo[:ref]`, shallow-clones it into
  `/opt/kcc`, and `exec`s `python /opt/kcc/kcc-c2e.py <your args>`.
- KCC's `kcc.py` `os.chdir()`s into its own install dir on Linux, so relative
  input/output paths would otherwise resolve against `/opt/kcc`. `entry.sh`
  absolutizes path-like args against your `/work` mount, so **bare filenames
  work** (`-o out file.cbz`, not `/work/...`).

## Notes

- `-f EPUB` avoids needing kindlegen. Use `-p KV` (Kindle Voyage) or any valid
  KCC profile.
- Output files land on your host owned by **root** (Docker runs as root). Remove with `sudo rm -rf out`, or: `docker run --rm -v "$PWD:/work" --entrypoint sh ghcr.io/nilsleo/kcc-run -c 'rm -rf /work/out'`.
- The image is rebuilt on every push and weekly (Mon 06:00 UTC) so the baked
  deps track upstream, via `.github/workflows/build.yml` → `ghcr.io/nilsleo/kcc-run`.

## Apple Silicon (ARM Macs)

The image is **linux/amd64 only** — on purpose. KCC's MOBI/AZW3 output needs
Amazon's `kindlegen`, which only ever shipped as a 32-bit **x86** binary (no ARM
build exists), so a native `arm64` image could never produce MOBI. Instead, run
the x86 image under emulation:

- Add `--platform linux/amd64` to every command (already in the examples above), or set it once so you can drop the flag:

  ```bash
  export DOCKER_DEFAULT_PLATFORM=linux/amd64
  ```

- **EPUB** works out of the box under emulation.
- **MOBI** needs 32-bit x86 emulation, which Rosetta does *not* provide. If MOBI fails, turn **off** Docker Desktop → Settings → General → "Use Rosetta for x86_64/amd64 emulation" (falls back to QEMU, which runs the 32-bit `kindlegen`). It's slower but works.

## Build locally

```bash
docker build -t ghcr.io/nilsleo/kcc-run .
```
