# otobo-texlive-provider

A small, independently versioned Docker image that provisions a full
[TeX Live](https://tug.org/texlive/) installation (including `lualatex`)
into a Docker volume, for use by [OTOBO](https://otobo.org) containers
that generate PDF documents (e.g. quotes and invoices) via LaTeX.

This image is intentionally **not** a variant of the OTOBO web image and
is **not** rebuilt on the OTOBO nightly build cycle. It exists purely to
decouple "installing TeX Live" from "building OTOBO", so that:

- the OTOBO web image stays small for the majority of installations that
  don't use LaTeX at all,
- TeX Live is only rebuilt when it actually needs to change (new packages,
  security updates), not every night,
- the same provider image can be reused across any number of OTOBO
  instances or customer deployments.

## How it works

The image does not run TeX Live itself. Instead, its entrypoint copies
the apt-installed TeX Live tree into a target directory (a mounted Docker
volume) and then exits. A one-shot **init container** pattern is used in
`docker-compose`:

```
texlive-init (this image)  --copies-->  texlive_data (named volume)
                                              |
                                              v
                                    otobo web / daemon container
                                    (mounts texlive_data read-only)
```

The OTOBO container never needs TeX Live baked in — it just mounts the
volume that this image populated and points its LaTeX-generation code at
the binary inside it via the `OTOBO_LUALATEX_BIN` environment variable.

See the [`otobo-docker`](https://github.com/RotherOSS/otobo-docker)
override file `docker-compose/otobo-override-latex.yml` for the full
integration.

## What's included

Installed via `apt` on top of `debian:trixie-slim`:

| Package                        | Purpose                                   |
|---------------------------------|--------------------------------------------|
| `texlive-luatex`                | Provides the `lualatex` binary             |
| `texlive-latex-recommended`     | Common LaTeX packages                      |
| `texlive-latex-extra`           | Additional packages (e.g. `tabularx`, `etoolbox`, `environ`) |
| `texlive-fonts-recommended`     | Standard font packages                     |
| `texlive-lang-german`           | German hyphenation / `babel`/`polyglossia` support |
| `lmodern`                       | Common font fix used by many templates     |

Adjust the package list in the `Dockerfile` if your `.tex` templates need
additional CTAN packages. Avoid `texlive-full` unless you actually need
it — it adds several GB to the image for packages most templates never
use.

## Important: Debian version must match the OTOBO base image

The OTOBO web image (see
[`otobo.web.dockerfile`](https://github.com/RotherOSS/otobo/blob/rel-11_1/otobo.web.dockerfile))
is built `FROM perl:5.44-slim-trixie`, i.e. **Debian 13 (trixie)**. The
binaries copied out of this image are linked against trixie's glibc and
shared libraries.

**This image's `FROM debian:trixie-slim` must be kept in lockstep with
the Debian release used by the OTOBO base image.** If OTOBO ever moves to
a newer Debian release, this image must be updated accordingly — otherwise
the copied binaries may fail at runtime with glibc/ABI mismatches when
mounted into the newer OTOBO container.

> **Upgrade checklist:** whenever bumping the OTOBO image version, check
> which Debian release `otobo.web.dockerfile`'s `perl:*-slim-*` base image
> uses, and update the `FROM` line here if it changed.

No other coupling to OTOBO's release cycle exists — this image doesn't
contain Perl, CPAN modules, or any OTOBO code, and does not need to be
rebuilt when OTOBO itself is rebuilt.

## Building

```bash
docker build -t myregistry/otobo-texlive-provider:2026.1 .
docker push myregistry/otobo-texlive-provider:2026.1
```

Tag with a meaningful version (date-based or semantic) rather than
`latest`, and pin that tag explicitly wherever the image is consumed —
see [Usage](#usage) below. This image is rebuilt on demand, not
automatically, so there is no "latest" that tracks a moving target.

## Usage

### Standalone

```bash
docker run --rm \
  -v texlive_data:/target \
  myregistry/otobo-texlive-provider:2026.1
```

This populates the `texlive_data` volume and exits with code `0`.

### With `otobo-docker` (recommended)

Add the following to `docker-compose/otobo-override-latex.yml` in your
[`otobo-docker`](https://github.com/RotherOSS/otobo-docker) setup:

```yaml
services:

  texlive-init:
    image: ${OTOBO_IMAGE_TEXLIVE:-myregistry/otobo-texlive-provider:2026.1}
    restart: "no"
    volumes:
      - texlive_data:/target

  web:
    depends_on:
      texlive-init:
        condition: service_completed_successfully
    volumes:
      - texlive_data:/opt/texlive-mounted:ro
    environment:
      OTOBO_LUALATEX_BIN: /opt/texlive-mounted/usr/bin/lualatex
      TEXMFVAR: /opt/otobo/var/tmp/texlive-cache/texmf-var
      TEXMFCACHE: /opt/otobo/var/tmp/texlive-cache

volumes:
  texlive_data: {}
```

Then add the override file to `COMPOSE_FILE` in your `.env`:

```
COMPOSE_FILE=docker-compose/otobo-base.yml:docker-compose/otobo-override-https.yml:docker-compose/otobo-override-latex.yml

OTOBO_IMAGE_TEXLIVE=myregistry/otobo-texlive-provider:2026.1
```

Installations that don't need LaTeX simply omit this file from
`COMPOSE_FILE` — the OTOBO web image itself is completely unaffected.

### Consuming the mounted binary from Perl code

Rather than relying on `$PATH` (which is resolved on the Docker host at
compose-file parse time, not inside the running container, and is
therefore not a reliable way to extend the container's runtime `PATH`),
point directly at the mounted binary via an environment variable:

```perl
my $LuaLaTeXBin = $ENV{OTOBO_LUALATEX_BIN} || 'lualatex';

my @Cmd = (
    $LuaLaTeXBin,
    '-interaction=nonstopmode',
    "--output-directory=$AbsOutputDir",
    $FileName,
);
```

### Cache / writable directories

`lualatex` needs a writable location for its format cache
(`luaotfload`) and generated `.fmt` files. Since the mounted volume is
read-only, point `TEXMFVAR` and `TEXMFCACHE` at a writable path inside
the existing `opt_otobo` volume (already mounted by the OTOBO containers)
rather than creating an additional named volume:

```yaml
environment:
  TEXMFVAR: /opt/otobo/var/tmp/texlive-cache/texmf-var
  TEXMFCACHE: /opt/otobo/var/tmp/texlive-cache
```

## Verifying a merged compose configuration

Before rolling this out, verify the fully merged compose configuration
(especially `depends_on`, which mixes short-form and long-form syntax
across files):

```bash
docker compose config
```

## Repository layout

```
.
├── Dockerfile        # builds the provider image
├── entrypoint.sh     # copies TeX Live into the mounted volume, then exits
└── README.md         # this file
```

## Versioning

Tags follow `<year>.<increment>` (e.g. `2026.1`, `2026.2`) and are bumped
whenever:

- the TeX Live package set changes (new packages added for a new template),
- a security update needs to be picked up from Debian,
- the Debian base release needs to track a change in the OTOBO base image
  (see [above](#important-debian-version-must-match-the-otobo-base-image)).

## License

_Add your organization's license here._
