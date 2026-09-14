# otobo-texlive-provider

A small, independently versioned Docker image that provisions a
self-contained, **relocatable upstream TeX Live** installation (including
`lualatex`) into a Docker volume, for use by [OTOBO](https://otobo.org)
containers that generate PDF documents (e.g. quotes and invoices) via
LaTeX.

This image is intentionally **not** a variant of the OTOBO web image and
is **not** rebuilt on the OTOBO nightly build cycle. It decouples
"installing TeX Live" from "building OTOBO", so that:

- the OTOBO web image stays small for the majority of installations that
  don't use LaTeX at all,
- TeX Live is only rebuilt when it actually needs to change,
- the same provider image can be reused across any number of OTOBO
  instances.

## Why upstream TeX Live and not Debian's `texlive-*` packages?

Debian's apt packages are **not relocatable**: `texmf.cnf`, kpathsea's
compiled-in defaults, `ls-R` databases (symlinks into `/var/lib/texmf`),
format files, shared libraries and script shebangs all hardcode absolute
paths under `/usr`, `/var` and `/etc`. Mounting such a tree at any other
path requires overriding one variable after another and still breaks in
surprising places.

Upstream TeX Live (installed with `install-tl` in *portable* mode) is
designed to be moved around: every path is resolved relative to the
binaries, `ls-R` files are plain files inside the tree, formats and
caches live inside the tree, and the binaries depend on nothing but
glibc/libstdc++. We install it to `/opt/texlive` and mount the volume in
the OTOBO container at that **same path** - so there is nothing to
relocate and nothing to override.

## How it works

```
texlive-init (this image)  --copies /opt/texlive-->  texlive_data (volume)
                                                            |
                                                            v
                                            otobo web / daemon container
                                            mounts it read-only at /opt/texlive
```

The consuming container only needs two environment variables:

| Variable             | Value                               | Purpose |
|----------------------|-------------------------------------|---------|
| `OTOBO_LUALATEX_BIN` | `/opt/texlive/bin/current/lualatex` | Absolute path used by the OTOBO Perl code. `bin/current` is an architecture-independent symlink (`x86_64-linux`, `aarch64-linux`, ...). |
| `TEXMFVAR`           | `/opt/otobo/var/tmp/texlive-var`    | Writable location for luaotfload's font caches. Everything pre-built at image build time is still read from the read-only tree. |

No `PATH`, `LD_LIBRARY_PATH`, `TEXMFCNF` or `TEXMF*` overrides are
required.

## What's included

- Base: `scheme-minimal` + `collection-basic`, `collection-latex`,
  `collection-luatex` (see `texlive.profile`)
- Packages on top: see [`tl-packages.txt`](tl-packages.txt) - e.g. `lm`,
  `fontspec`, `environ`, `etoolbox`, `titlesec`, `babel-german`.
- Pre-built at image build time: `lualatex.fmt`, luaotfload's font name
  database, and warmed caches for the Latin Modern fonts.
- A build-time smoke test (`smoke-test.tex`) compiles a document with the
  same package stack as the OTOBO templates. A missing package fails the
  image build instead of a production request.

Custom fonts used by the OTOBO templates via `\setmainfont{...}[Path=fonts/]`
are **not** part of this image: fontspec loads them relative to the `.tex`
file, so they ship together with the templates.

## Adding packages

1. Find the package for a missing file:
   ```bash
   docker run --rm --entrypoint tlmgr rotheross/otobo-texlive-provider:latest \
       search --global --file /siunitx.sty
   ```
2. Add the package name to `tl-packages.txt`.
3. Optionally add a `\usepackage{...}` line to `smoke-test.tex` so the
   build verifies it.
4. Commit and push; Docker Hub rebuilds the image.

## Reproducible builds

`TL_REPO` (build arg) selects the TeX Live network repository. The
default, `https://mirror.ctan.org/systems/texlive/tlnet`, is the *current*
release and therefore a moving target. For production, pin it to a
frozen snapshot, either in the Dockerfile default or via the Docker Hub
build settings:

```
# dated snapshot (any day):
https://texlive.info/tlnet-archive/2026/09/01/tlnet
# frozen final state of a past release:
https://ftp.math.utah.edu/pub/tex/historic/systems/texlive/2025/tlnet-final
```

`instopt_adjustrepo 0` in `texlive.profile` makes sure the installation
keeps using exactly that repository afterwards.

## Compatibility with the OTOBO image

The only remaining coupling to the OTOBO base image is the C library: the
TeX Live binaries need a glibc and libstdc++ at least as new as the ones
they were built against. Both this image (`debian:trixie-slim`) and the
OTOBO web image (`perl:*-slim-trixie`) are based on the same Debian
release, so this is satisfied. If OTOBO moves to a newer Debian release,
this image keeps working; only the reverse (OTOBO on an *older* Debian
than this image) could be a problem.

## Usage with `otobo-docker`

1. Copy `docker-compose/otobo-override-latex.yml` into the
   `docker-compose/` folder of your
   [`otobo-docker`](https://github.com/RotherOSS/otobo-docker) checkout.
2. Append it to `COMPOSE_FILE` in `.env` and pin the image:
   ```
   COMPOSE_FILE=docker-compose/otobo-base.yml:docker-compose/otobo-override-https.yml:docker-compose/otobo-override-latex.yml
   OTOBO_IMAGE_TEXLIVE=rotheross/otobo-texlive-provider:latest
   ```
3. `docker compose up -d`

Installations that don't need LaTeX simply omit the override file; the
OTOBO image itself is unaffected.

See [SETUP.md](SETUP.md) for the step-by-step rollout and verification.

## Perl side

```perl
my $LuaLaTeXBin = $ENV{OTOBO_LUALATEX_BIN} || 'lualatex';

# luaotfload creates its cache directories itself, but creating the root
# up front avoids relying on that.
File::Path::make_path( $ENV{TEXMFVAR} ) if $ENV{TEXMFVAR} && !-d $ENV{TEXMFVAR};
```

## Troubleshooting

| Symptom | Check |
|---|---|
| `texlive-init` exits non-zero | `docker compose logs texlive-init` - the entrypoint verifies `lualatex`, `ls-R` and `lualatex.fmt` after copying and reports which one is missing. |
| `! LaTeX Error: File 'xyz.sty' not found.` | Package missing: see *Adding packages*. |
| `luaotfload | db : Font names database not found` or slow first run | `TEXMFVAR` must point to a writable directory; check `docker compose exec web sh -c 'touch "$TEXMFVAR/x"'`. |
| `error while loading shared libraries` | glibc/libstdc++ mismatch - see *Compatibility*. |

Quick end-to-end check inside the running web container:

```bash
docker compose exec web sh -c '"$OTOBO_LUALATEX_BIN" --version | head -1'
docker compose exec web sh -c '/opt/texlive/bin/current/kpsewhich ot1lmr.fd fontspec.sty'
docker compose exec web sh -c '
  cd /tmp && printf "\\documentclass{article}\\usepackage{fontspec}\\begin{document}Hallo äöü\\end{document}" > t.tex &&
  "$OTOBO_LUALATEX_BIN" -interaction=nonstopmode -halt-on-error t.tex >/dev/null && ls -l t.pdf'
```

## Repository layout

```
.
├── Dockerfile                                  # installs upstream TeX Live to /opt/texlive
├── texlive.profile                             # install-tl profile (portable, minimal scheme)
├── tl-packages.txt                             # packages installed on top (edit me)
├── smoke-test.tex                              # build-time verification document
├── entrypoint.sh                               # copies /opt/texlive into the mounted volume
├── docker-compose/otobo-override-latex.yml     # compose override for otobo-docker
├── SETUP.md
└── README.md
```

## License

GNU General Public License v3 or later - see [LICENSE](LICENSE).
