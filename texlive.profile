# install-tl profile for otobo-texlive-provider.
#
# "portable 1" is the key setting: it keeps TEXMFHOME/TEXMFVAR/TEXMFCONFIG
# inside TEXDIR, making the whole installation a single, self-contained,
# relocatable directory tree with no references outside of /opt/texlive.
#
# Reference: https://tug.org/texlive/doc/install-tl.html#PROFILES

selected_scheme scheme-minimal

TEXDIR /opt/texlive
# Keep every tree inside TEXDIR (portable mode implies this, but be explicit
# so the layout does not depend on install-tl defaults).
TEXMFLOCAL /opt/texlive/texmf-local
TEXMFSYSVAR /opt/texlive/texmf-var
TEXMFSYSCONFIG /opt/texlive/texmf-config
TEXMFHOME /opt/texlive/texmf-home
TEXMFVAR /opt/texlive/texmf-var
TEXMFCONFIG /opt/texlive/texmf-config

# Collections (packages on top are installed via tlmgr, see tl-packages.txt)
collection-basic 1
collection-latex 1
collection-luatex 1

# Installation options
instopt_portable 1
instopt_adjustpath 0
# Do NOT switch the repository to mirror.ctan.org after installation -
# keep using exactly the repository given at build time (reproducibility).
instopt_adjustrepo 0
instopt_letter 0

# tlpdb options
tlpdbopt_install_docfiles 0
tlpdbopt_install_srcfiles 0
tlpdbopt_autobackup 0
tlpdbopt_backupdir tlpkg/backups
tlpdbopt_create_formats 1
tlpdbopt_post_code 1
tlpdbopt_desktop_integration 0
tlpdbopt_file_assocs 0
