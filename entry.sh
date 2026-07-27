#!/bin/sh
# Clone <owner/repo[:ref]> at runtime and run KCC's CLI with the remaining args.
#   entry.sh NilsLeo/kcc:up/image-resilience -p KV -f EPUB -o out file.pdf
set -e

if [ -z "$1" ]; then
  echo "usage: <owner/repo[:ref]> <kcc-c2e.py args...>" >&2
  echo "  e.g. NilsLeo/kcc:up/image-resilience -p KV -f EPUB -o out file.pdf" >&2
  exit 2
fi

spec="$1"; shift
repo="${spec%%:*}"
ref="${spec#*:}"
[ "$ref" = "$spec" ] && ref="master"   # no ':' given → default branch

echo ">> github.com/$repo @ $ref" >&2
rm -rf /opt/kcc
git clone --depth=1 --branch "$ref" "https://github.com/$repo.git" /opt/kcc >/dev/null 2>&1 \
  || { echo "!! clone failed for $repo@$ref" >&2; exit 3; }

# KCC's kcc.py modify_path() os.chdir()s into its own install dir on Linux, so
# relative input/output paths would resolve against /opt/kcc, not your mount.
# Absolutize path-like args (relative to the current /work dir) up front so the
# one-liner can use bare filenames: `-o out file.cbz` instead of `/work/...`.
prev=""
n=$#
while [ "$n" -gt 0 ]; do
  a="$1"; shift
  case "$a" in
    /*|-*)                                    # already absolute, or a flag
      na="$a" ;;
    *)
      if [ -e "$a" ] || [ "$prev" = "-o" ] || [ "$prev" = "--output" ]; then
        na="$PWD/$a"                          # existing input, or the output dir
      else
        na="$a"                               # a flag value (KV, EPUB, …)
      fi ;;
  esac
  set -- "$@" "$na"
  prev="$a"
  n=$((n - 1))
done

exec python /opt/kcc/kcc-c2e.py "$@"
