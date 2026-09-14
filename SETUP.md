# Setup: LaTeX/lualatex support for OTOBO (docker-compose)

Adds LaTeX support (used to generate quotes/invoices) to an existing
`otobo-docker` deployment without changing the OTOBO web image.

## 1. Build the provider image

The image is built automatically by Docker Hub from this repository
(Automated Build). After pushing a change:

- Docker Hub -> repository -> **Builds**: wait until the build for your
  commit shows **Success**. The build takes several minutes (TeX Live
  download + format/cache generation + smoke test).
- Open the build log if it fails. The most common cause is a missing
  package, which the smoke test reports as
  `! LaTeX Error: File 'xyz.sty' not found.`

## 2. Add the override file to your otobo-docker checkout

Copy `docker-compose/otobo-override-latex.yml` into the existing
`docker-compose/` folder of your `otobo-docker` checkout.

## 3. Update `.env`

Append the override to `COMPOSE_FILE` and pin the image:

```
COMPOSE_FILE=docker-compose/otobo-base.yml:docker-compose/otobo-override-https.yml:docker-compose/otobo-override-latex.yml

OTOBO_IMAGE_TEXLIVE=rotheross/otobo-texlive-provider:latest
```

## 4. Verify the merged configuration

```bash
docker compose config | grep -A12 'texlive'
```

`web` (and `daemon`) must show the `texlive_data:/opt/texlive:ro` mount
and the `OTOBO_LUALATEX_BIN` / `TEXMFVAR` environment variables.

## 5. Roll out (production-safe, no `down`)

```bash
docker compose pull texlive-init
docker compose up -d --force-recreate texlive-init   # repopulates the volume
docker compose logs texlive-init                     # must end with "TeX Live provisioning done"
docker compose up -d --force-recreate web daemon     # only needed when the env vars changed
```

`web`/`daemon` see changes to the volume contents immediately; they only
need to be recreated when the compose *definition* (mounts, environment)
changed. `texlive-init` verifies the copied tree and exits non-zero if
anything essential is missing, in which case `web`/`daemon` will not be
started by `depends_on`.

## 6. Verify inside the web container

```bash
docker compose exec web sh -c '"$OTOBO_LUALATEX_BIN" --version | head -1'
docker compose exec web sh -c '/opt/texlive/bin/current/kpsewhich ot1lmr.fd fontspec.sty environ.sty'
docker compose exec web sh -c '
  cd /tmp && printf "\\documentclass{article}\\usepackage{fontspec}\\begin{document}Hallo äöü\\end{document}" > t.tex &&
  "$OTOBO_LUALATEX_BIN" -interaction=nonstopmode -halt-on-error t.tex >/dev/null && ls -l t.pdf'
```

All three must succeed (version line, three paths, a non-empty `t.pdf`).

## 7. Perl side

Read the binary path from the environment and make sure the writable
cache directory exists:

```perl
my $LuaLaTeXBin = $ENV{OTOBO_LUALATEX_BIN} || 'lualatex';

if ( $LuaLaTeXBin =~ m{/} && !-x $LuaLaTeXBin ) {
    return ( -1, '', "lualatex binary not found or not executable: $LuaLaTeXBin" );
}

File::Path::make_path( $ENV{TEXMFVAR} ) if $ENV{TEXMFVAR} && !-d $ENV{TEXMFVAR};

my @Cmd = (
    $LuaLaTeXBin,
    '-interaction=nonstopmode',
    "--output-directory=$AbsOutputDir",
    $FileName,
);
```

## 8. Test with the real templates

Trigger the OTOBO process that generates a quote/invoice. The custom fonts
are loaded via `Path=fonts/` relative to the generated `.tex` file, so the
`fonts/` directory must exist next to it - that is independent of this
image. The first run caches the custom fonts' glyph data under `TEXMFVAR`
and is therefore a bit slower than subsequent runs.

## Rolling back / disabling

Remove `:docker-compose/otobo-override-latex.yml` from `COMPOSE_FILE` and
run `docker compose up -d`. No image rebuild required.
