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
# This image is built independently of the OTOBO nightly build cycle -
# only rebuild it when the TeX Live version or package set should change.
#
# IMPORTANT: the Debian release below must match the Debian release used
# by the OTOBO web image (see otobo.web.dockerfile, currently based on
# perl:5.44-slim-trixie -> Debian 13 "trixie"). Keep this in lockstep
# whenever OTOBO's base image changes, otherwise the binaries copied out
# of this image may fail with glibc/ABI mismatches when mounted into a
# newer OTOBO container. See README.md for details.

FROM debian:trixie-slim

RUN apt-get update \
 && DEBIAN_FRONTEND=noninteractive apt-get -y --no-install-recommends install \
    texlive-luatex \
    texlive-latex-recommended \
    texlive-latex-extra \
    texlive-fonts-recommended \
    texlive-lang-german \
    lmodern \
 && rm -rf /var/lib/apt/lists/*

COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

ENTRYPOINT ["/entrypoint.sh"]
