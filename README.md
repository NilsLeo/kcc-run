# kcc-run

Run **any [KCC](https://github.com/ciromattia/kcc) fork/branch's CLI** against a
file, in a throwaway container. The KCC `owner/repo:ref` is a **runtime
argument**, so one image reproduces and A/B-tests conversion bugs across
branches without rebuilding.

```
docker run --rm -v "$PWD:/work" ghcr.io/nilsleo/kcc-run  <owner/repo[:ref]>  <kcc-c2e.py args...>
```

## Quick start

```bash
docker pull ghcr.io/nilsleo/kcc-run:latest

# upstream master (default branch if you omit :ref)
docker run --rm -v "$PWD:/work" ghcr.io/nilsleo/kcc-run \
  ciromattia/kcc:master           -p KV -f EPUB -o out mybook.cbz

# a fork's feature branch — same image, no rebuild
docker run --rm -v "$PWD:/work" ghcr.io/nilsleo/kcc-run \
  NilsLeo/kcc:up/image-resilience -p KV -f EPUB -o out mybook.cbz
```

A shell shortcut so it reads exactly like `repo:ref  cli args`:

```bash
kcc() { docker run --rm -v "$PWD:/work" -w /work ghcr.io/nilsleo/kcc-run "$@"; }

kcc ciromattia/kcc:master           -p KV -f EPUB -o out mybook.cbz
kcc NilsLeo/kcc                     -p KV -f EPUB -o out mybook.pdf   # no :ref → master
```

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
- Output files land on your host owned by **root** (Docker runs as root). Remove
  with `sudo rm -rf out`, or:
  `docker run --rm -v "$PWD:/work" --entrypoint sh ghcr.io/nilsleo/kcc-run -c 'rm -rf /work/out'`.
- The image is rebuilt on every push and weekly (Mon 06:00 UTC) so the baked
  deps track upstream, via `.github/workflows/build.yml` → `ghcr.io/nilsleo/kcc-run`.

## Build locally

```bash
docker build -t ghcr.io/nilsleo/kcc-run .
```
