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

# Dockerfile for otobo-texlive-provider.
#
# Installs *upstream* TeX Live (via install-tl) into /opt/texlive in
# "portable" mode. Unlike Debian's apt packages, upstream TeX Live is
# designed to be relocatable: every path is resolved relative to the
# location of the binaries, ls-R databases are plain files inside the
# tree, formats and caches live inside the tree, and the binaries have
# almost no external library dependencies. The consuming OTOBO container
# mounts the resulting tree at the *same* path (/opt/texlive), so nothing
# needs to be relocated or overridden at runtime.
#
# This image is built independently of the OTOBO nightly build cycle -
# only rebuild it when the TeX Live version or the package set should
# change (see tl-packages.txt).

FROM debian:trixie-slim

# TeX Live network repository used for install-tl and tlmgr.
#
# The default (mirror.ctan.org) always points at the *current* TeX Live
# release and is a moving target. For reproducible builds, pin to a
# frozen snapshot instead, e.g. a dated tlnet archive:
#   https://texlive.info/tlnet-archive/2026/09/01/tlnet
# or the frozen final state of a past release:
#   https://ftp.math.utah.edu/pub/tex/historic/systems/texlive/2025/tlnet-final
ARG TL_REPO=https://mirror.ctan.org/systems/texlive/tlnet

ENV TEXLIVE_DIR=/opt/texlive

# perl is required by install-tl and tlmgr; the rest is for downloading.
RUN apt-get update \
 && DEBIAN_FRONTEND=noninteractive apt-get -y --no-install-recommends install \
      perl \
      wget \
      ca-certificates \
      xz-utils \
      gnupg \
 && rm -rf /var/lib/apt/lists/*

# Base installation according to texlive.profile (minimal scheme plus
# the basic/latex/luatex collections, portable mode, no docs/sources).
COPY texlive.profile /tmp/texlive.profile
RUN set -eu; \
    mkdir -p /tmp/install-tl; \
    wget -qO- "${TL_REPO}/install-tl-unx.tar.gz" \
      | tar xz -C /tmp/install-tl --strip-components=1; \
    /tmp/install-tl/install-tl \
      --profile=/tmp/texlive.profile \
      --repository "${TL_REPO}"; \
    rm -rf /tmp/install-tl /tmp/texlive.profile; \
    # TeX Live puts binaries in an architecture-specific directory
    # (x86_64-linux, aarch64-linux, ...). Provide a stable, architecture-
    # independent alias so consumers never need to know the triplet.
    ARCH_DIR="$(ls "${TEXLIVE_DIR}/bin" | head -n 1)"; \
    ln -s "${ARCH_DIR}" "${TEXLIVE_DIR}/bin/current"

ENV PATH="${TEXLIVE_DIR}/bin/current:${PATH}"

# Install exactly the packages the OTOBO LaTeX templates need.
# tlmgr resolves dependencies automatically. Edit tl-packages.txt to
# add or remove packages - no Dockerfile change required.
COPY tl-packages.txt /tmp/tl-packages.txt
RUN set -eu; \
    grep -vE '^[[:space:]]*(#|$)' /tmp/tl-packages.txt | xargs tlmgr install; \
    rm -f /tmp/tl-packages.txt; \
    # Pre-build the lualatex format so mktexfmt is never needed at runtime.
    fmtutil-sys --byfmt lualatex; \
    # Pre-build luaotfload's font name database (scans the TeX Live fonts).
    luaotfload-tool --update --force; \
    # Refresh the ls-R databases of all trees (texmf-var now contains the
    # format file; the tree is marked "!!" = ls-R-only in texmf.cnf).
    mktexlsr

# Build-time smoke test: compile a small document that uses the same
# package stack as the OTOBO templates. This fails the image build early
# if a package is missing, and as a side effect warms luaotfload's glyph
# cache for the default (Latin Modern) fonts, which is then shipped
# read-only inside the tree.
COPY smoke-test.tex /tmp/smoke/smoke-test.tex
RUN set -eu; \
    cd /tmp/smoke; \
    lualatex -interaction=nonstopmode -halt-on-error smoke-test.tex >/dev/null; \
    test -s smoke-test.pdf; \
    echo "smoke test OK: $(stat -c %s smoke-test.pdf) bytes"; \
    cd /; rm -rf /tmp/smoke

COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

ENTRYPOINT ["/entrypoint.sh"]
