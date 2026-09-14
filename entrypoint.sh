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
# Copies the self-contained TeX Live tree from this image (/opt/texlive)
# into a target directory (a mounted Docker volume, default /target) and
# exits. The consuming OTOBO container mounts that volume at the very same
# path, /opt/texlive, so no path relocation is needed at runtime.
#
# See README.md for how this is wired up via docker-compose.

set -eu

SOURCE_DIR="${TEXLIVE_DIR:-/opt/texlive}"
TARGET_DIR="${TARGET_DIR:-/target}"

echo "Provisioning TeX Live from ${SOURCE_DIR} into ${TARGET_DIR} ..."

if [ ! -d "${TARGET_DIR}" ]; then
    echo "ERROR: target directory ${TARGET_DIR} does not exist - is the volume mounted?" >&2
    exit 1
fi

# Start from a clean slate on every run, so re-running this container
# (e.g. after the image was rebuilt) never leaves stale files behind.
# Only the *contents* are removed, never the mount point itself.
find "${TARGET_DIR}" -mindepth 1 -maxdepth 1 -exec rm -rf {} +

cp -a "${SOURCE_DIR}/." "${TARGET_DIR}/"

# Sanity checks: fail loudly instead of leaving a half-usable volume.
test -x "${TARGET_DIR}/bin/current/lualatex" \
    || { echo "ERROR: lualatex missing after copy" >&2; exit 1; }
test -s "${TARGET_DIR}/texmf-dist/ls-R" \
    || { echo "ERROR: texmf-dist/ls-R missing after copy" >&2; exit 1; }
find "${TARGET_DIR}/texmf-var/web2c" -name 'lualatex.fmt' | grep -q . \
    || { echo "ERROR: pre-built lualatex.fmt missing after copy" >&2; exit 1; }

echo "TeX Live provisioning done ($(du -sh "${TARGET_DIR}" | cut -f1))."
