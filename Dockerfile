# kcc-run — run any KCC fork/branch's CLI against a file, in a throwaway container.
# The KCC repo:ref is a RUNTIME argument, so one image runs any fork/branch:
#   docker build -t ghcr.io/nilsleo/kcc-run .
#   docker run --rm -v "$PWD:/work" ghcr.io/nilsleo/kcc-run <owner/repo[:ref]> <kcc-c2e.py args...>
FROM python:3.11-slim

# kindlegen is a 32-bit i386 binary → needs i386 runtime libs.
# unrar (non-free) is what KCC shells out to for .cbr/RAR on Linux (it only tries
# `unar` on macOS); enable the non-free component to install it. p7zip can't
# extract many RARs. Keep `unar` too as a free fallback.
RUN dpkg --add-architecture i386 \
 && sed -i 's/^Components: main$/Components: main contrib non-free non-free-firmware/' /etc/apt/sources.list.d/debian.sources \
 && apt-get update && apt-get install -y --no-install-recommends \
      git p7zip-full unrar unar curl ca-certificates \
      libc6-i386 lib32stdc++6 \
 && rm -rf /var/lib/apt/lists/*

# kindlegen (needed for -f MOBI/AZW3). Placed OUTSIDE /opt/kcc — entry.sh wipes
# /opt/kcc on every run — and put on PATH so KCC finds it.
RUN curl -fsSL https://archive.org/download/kindlegen/kindlegen -o /opt/kindlegen \
 && chmod +x /opt/kindlegen \
 && ln -s /opt/kindlegen /usr/local/bin/kindlegen

# Bake the (branch-independent) Python deps once, using upstream master's list as
# the baseline — the runtime clone reuses them.
RUN git clone --depth=1 https://github.com/ciromattia/kcc.git /tmp/kcc-base \
 && pip install --no-cache-dir numpy PyMuPDF boto3 \
 && pip install --no-cache-dir -r /tmp/kcc-base/requirements-docker.txt \
 && rm -rf /tmp/kcc-base

COPY entry.sh /usr/local/bin/entry.sh
COPY fetch.py /usr/local/bin/fetch.py
RUN chmod +x /usr/local/bin/entry.sh

WORKDIR /work
ENTRYPOINT ["/usr/local/bin/entry.sh"]
