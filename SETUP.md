# Setup: LaTeX/lualatex support for OTOBO (docker-compose)

This adds LaTeX support (used to generate quotes/invoices) to an existing
`otobo-docker` deployment, without changing the OTOBO web image itself.

## 1. Build and publish the provider image

In the `otobo-texlive-provider` repo:

```bash
docker build -t myregistry/otobo-texlive-provider:2026.1 .
docker push myregistry/otobo-texlive-provider:2026.1
```

Only needs to be rebuilt when the TeX Live package set changes - not on
every OTOBO nightly build.

## 2. Add the override file to your otobo-docker checkout

Copy `docker-compose/otobo-override-latex.yml` from this delivery into
your `otobo-docker` checkout, into the existing `docker-compose/` folder
(same location as `otobo-override-https.yml` etc.).

## 3. Update your `.env`

Two options:

- **Fresh setup:** copy `.docker_compose_env_https_latex` to `.env` and
  fill in the required values (`OTOBO_DB_ROOT_PASSWORD`,
  `OTOBO_NGINX_SSL_CERTIFICATE*`, ...), same as with any other
  `.docker_compose_env_*` sample file.
- **Existing setup:** in your current `.env`, append
  `:docker-compose/otobo-override-latex.yml` to `COMPOSE_FILE`, and add:
  ```
  OTOBO_IMAGE_TEXLIVE=myregistry/otobo-texlive-provider:2026.1
  ```

## 4. Verify the merged configuration

```bash
docker compose config
```

Check that:
- `texlive-init` appears as a service,
- `web` (and `daemon`, if included) lists `texlive-init` under
  `depends_on` with `condition: service_completed_successfully`,
- `web`/`daemon` have the `texlive_data` volume mount and the
  `OTOBO_LUALATEX_BIN` / `TEXMFVAR` / `TEXMFCACHE` environment variables.

## 5. Start the environment

```bash
docker compose up -d
docker compose logs texlive-init
```

`texlive-init` should log `TeX Live provisioning done.` and then exit
with code `0`. Confirm with:

```bash
docker compose ps texlive-init
# STATUS should show "Exited (0)"
```

`web` and `daemon` will wait for this before starting, due to
`condition: service_completed_successfully`.

## 6. Point the Perl code at the mounted binary

In `_RunLuaLaTeXOnce` (or wherever `lualatex` is invoked), read the
binary path from the environment instead of relying on `$PATH`:

```perl
my $LuaLaTeXBin = $ENV{OTOBO_LUALATEX_BIN} || 'lualatex';

my @Cmd = (
    $LuaLaTeXBin,
    '-interaction=nonstopmode',
    "--output-directory=$AbsOutputDir",
    $FileName,
);
```

## 7. Smoke test

```bash
docker compose exec web sh -c '$OTOBO_LUALATEX_BIN --version'
```

If this prints the lualatex version, the mount and environment variables
are wired up correctly and your process code should be able to render
PDFs as before.

## Rolling back / disabling

Remove `:docker-compose/otobo-override-latex.yml` from `COMPOSE_FILE`
(and the `OTOBO_IMAGE_TEXLIVE` line, optional) and run
`docker compose up -d` again. `web`/`daemon` return to the plain OTOBO
image behavior; no image rebuild required.
