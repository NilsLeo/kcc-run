#!/usr/bin/env python3
"""Download an input file by job uuid from the storage bucket into the CWD.
Prints the local filename on stdout. Invoked by entry.sh for `--uuid <id>`.

Env (pass via `docker run --env-file .env.prod` or `-e`):
  KCC_BUCKET  (or S3_ERRORS_BUCKET / S3_BUCKET; default: mangaconverter-errors)
  S3_ENDPOINT S3_REGION S3_ACCESS_KEY_ID S3_SECRET_ACCESS_KEY
"""
import os
import sys
import boto3
from botocore.config import Config

uuid = sys.argv[1] if len(sys.argv) > 1 else ""
if not uuid:
    sys.stderr.write("fetch.py: missing uuid\n")
    sys.exit(2)

bucket = (os.environ.get("KCC_BUCKET") or os.environ.get("S3_ERRORS_BUCKET")
          or os.environ.get("S3_BUCKET") or "mangaconverter-errors")

s3 = boto3.client(
    "s3",
    region_name=os.environ.get("S3_REGION"),
    endpoint_url=os.environ.get("S3_ENDPOINT"),
    aws_access_key_id=os.environ.get("S3_ACCESS_KEY_ID"),
    aws_secret_access_key=os.environ.get("S3_SECRET_ACCESS_KEY"),
    config=Config(s3={"addressing_style": "path"}),  # Hetzner/MinIO path-style
)

key = None
for page in s3.get_paginator("list_objects_v2").paginate(Bucket=bucket):
    for obj in page.get("Contents", []):
        if uuid in obj["Key"]:
            key = obj["Key"]
            break
    if key:
        break

if not key:
    sys.stderr.write(f"fetch.py: no object containing '{uuid}' in bucket '{bucket}'\n")
    sys.exit(4)

name = os.path.basename(key)
s3.download_file(bucket, key, name)  # CWD is /work
print(name)
