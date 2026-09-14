#!/bin/sh

# --
# OTOBO is a web-based ticketing system for service organisations.
# --
# Copyright (C) 2019-2026 Rother OSS GmbH, https://otobo.io/
# --
# This program is free software: you can redistribute it and/or modify it under
# the terms of the GNU General Public License as published by the Free Software
# Foundation, either version 3 of the License, or (at your option) any later version.
# This program is distributed in the hope that it will be useful, but WITHOUT
# ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS
# FOR A PARTICULAR PURPOSE. See the GNU General Public License for more details.
# You should have received a copy of the GNU General Public License
# along with this program. If not, see <https://www.gnu.org/licenses/>.
# --

# entrypoint.sh
#
# Copies the apt-installed TeX Live environment from this image into a
# target directory (expected to be a mounted Docker volume, e.g. /target)
# and then exits. This container does not run TeX Live itself - it only
# provisions it for another container to mount.
#
# See README.md for how this is wired up via docker-compose.

set -eu

TARGET_DIR="${TARGET_DIR:-/target}"

echo "Provisioning TeX Live into ${TARGET_DIR} ..."

# Start from a clean slate on every run, so re-running this container
# (e.g. after bumping the image tag) never leaves stale files from a
# previous, possibly incomplete, provisioning.
rm -rf "${TARGET_DIR}/usr" "${TARGET_DIR}/etc"
mkdir -p "${TARGET_DIR}/usr/bin"
mkdir -p "${TARGET_DIR}/usr/share"
mkdir -p "${TARGET_DIR}/usr/lib"

# Binaries (lualatex, kpsewhich, mktexfmt, ...)
cp -a /usr/bin/. "${TARGET_DIR}/usr/bin/"

# TeX Live package tree and texmf trees.
# These may not all exist depending on the installed package set, so
# failures here are tolerated individually.
cp -a /usr/share/texlive "${TARGET_DIR}/usr/share/" 2>/dev/null || true
cp -a /usr/share/texmf "${TARGET_DIR}/usr/share/" 2>/dev/null || true
cp -a /usr/share/texmf-dist "${TARGET_DIR}/usr/share/" 2>/dev/null || true

# Shared libraries needed by lualatex/luahbtex and friends
# (libtexlua53, libkpathsea, libptexenc, ...). These live under the
# architecture-specific multiarch directory, e.g. /usr/lib/x86_64-linux-gnu
# on amd64 or /usr/lib/aarch64-linux-gnu on arm64. We copy that directory
# under a stable, architecture-independent name so the consuming
# docker-compose file doesn't need to know or guess the triplet.
MULTIARCH_DIR=$(find /usr/lib -maxdepth 1 -type d -name '*-linux-gnu*' | head -n 1)
if [ -n "${MULTIARCH_DIR}" ]; then
    echo "Copying shared libraries from ${MULTIARCH_DIR} ..."
    mkdir -p "${TARGET_DIR}/usr/lib/texlive-libs"
    cp -a "${MULTIARCH_DIR}/." "${TARGET_DIR}/usr/lib/texlive-libs/"
else
    echo "WARNING: could not detect multiarch lib directory - lualatex will likely fail to load shared libraries" >&2
fi

# System-wide texmf config, if present.
if [ -d /etc/texmf ]; then
    mkdir -p "${TARGET_DIR}/etc/texmf"
    cp -a /etc/texmf/. "${TARGET_DIR}/etc/texmf/"
fi

# Pre-built lualatex.fmt and associated cache, generated at image-build
# time (see Dockerfile). Copied read-only into the volume; TEXMFVAR in
# the consuming container points here, so mktexfmt is never invoked at
# runtime.
mkdir -p "${TARGET_DIR}/texmf-var-prebuilt"
cp -a /opt/texmf-var-prebuilt/. "${TARGET_DIR}/texmf-var-prebuilt/"

# Regenerate the ls-R filename database against the *copied* files, so it
# reflects the exact post-copy state instead of a stale build-time
# snapshot. kpathsea (used both for classic file lookups like .fd files
# and, via the "kpse lua searcher", for LuaTeX's runtime require() of Lua
# modules such as luaotfload-main, expl3, ltluatex) relies heavily on
# this database - a stale or missing one causes "file/module not found"
# errors even though the files physically exist under the mount.
#
# If mktexlsr fails for any reason, fall back to removing ls-R entirely,
# which forces kpathsea to fall back to a live (slower, but always
# consistent) directory scan instead of trusting a broken database.
echo "Regenerating ls-R filename database ..."
if ! mktexlsr "${TARGET_DIR}/usr/share/texmf-dist" "${TARGET_DIR}/usr/share/texmf" 2>&1; then
    echo "WARNING: mktexlsr failed - removing ls-R to force live directory scans" >&2
    find "${TARGET_DIR}/usr/share" -name "ls-R" -delete
fi

echo "TeX Live provisioning done."
