#!/bin/sh
# Clone <owner/repo[:ref]> at runtime and run KCC's CLI with the remaining args.
#   entry.sh NilsLeo/kcc:up/image-resilience -p KV -f EPUB -o out file.pdf
set -e

if [ -z "$1" ]; then
  echo "usage: <owner/repo[:ref]> <kcc-c2e.py args...>" >&2
  echo "  e.g. NilsLeo/kcc:up/image-resilience -p KV -f EPUB -o out file.pdf" >&2
  echo "  --uuid <job-uuid>: fetch that input from the storage bucket and use it" >&2
  echo "     as the input file. Needs S3_* env vars (S3_ENDPOINT/S3_REGION/" >&2
  echo "     S3_ACCESS_KEY_ID/S3_SECRET_ACCESS_KEY; bucket via KCC_BUCKET/" >&2
  echo "     S3_ERRORS_BUCKET/S3_BUCKET). Pass them via --env-file .env.prod." >&2
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

# --uuid <id>: fetch that input from the storage bucket into ./ and use it as the input.
uuid=""
count=$#
while [ "$count" -gt 0 ]; do
  a="$1"; shift; count=$((count - 1))
  if [ "$a" = "--uuid" ]; then
    uuid="$1"; shift; count=$((count - 1))   # consume its value
    continue
  fi
  set -- "$@" "$a"                            # keep every other arg, in order
done
if [ -n "$uuid" ]; then
  echo ">> fetching uuid $uuid from ${KCC_BUCKET:-${S3_ERRORS_BUCKET:-mangaconverter-errors}}" >&2
  fname=$(python /usr/local/bin/fetch.py "$uuid") || { echo "!! fetch failed for $uuid" >&2; exit 4; }
  echo ">> downloaded: $fname" >&2
  # Append as an absolute path: bucket keys can start with '-' (e.g.
  # "-Batchmanga.com-…zip"), which KCC's argparse would otherwise treat as a
  # flag. An absolute path also skips the absolutize loop's flag branch below.
  case "$fname" in
    /*) set -- "$@" "$fname" ;;
    *)  set -- "$@" "$PWD/$fname" ;;
  esac
fi

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
