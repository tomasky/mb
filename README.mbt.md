# mb

A MoonBit-native take on [uv](https://github.com/astral-sh/uv): a small,
fast toolchain and package manager for MoonBit, written in MoonBit.

`mb` manages two things, mirroring how `uv python` / `uv run` / `uv tool`
manage Python:

- **MoonBit toolchains** — download, install and switch between compiler
  releases from `cli.moonbitlang.com` (`mb moon ...`).
- **Tools** — install a prebuilt binary from a module's GitHub release,
  falling back to downloading a module from
  [mooncakes.io](https://mooncakes.io) and compiling it (`mb tool ...`).

Everything installs to `~/.local/bin` by default. Only Linux (`x86_64`,
`aarch64`) and macOS on Apple Silicon (`arm64`) are supported: the MoonBit
toolchain no longer ships an Intel macOS target, so there is no
`darwin-x86_64` build.

## Install

```bash
curl -LsSf https://raw.githubusercontent.com/tomasky/mb/main/install.sh | bash
```

Or with npm:

```bash
pnpm install -g @tomasko/mb
```

Both download the prebuilt binary from
[GitHub Releases](https://github.com/tomasky/mb/releases) for the current
platform. See [Build](#build) to compile from source.

## Build

```bash
moon build --target native --release
# binary: _build/native/release/build/cmd/mb/mb.exe
```

## Usage

```
mb run [--moon <version>] <command> [args...]
mb moon list | install [version] | uninstall <version> | default <version> | which [version] | latest
mb tool install <author>/<module>[@<version>] [--force] [--bin-dir <dir>] [--moon <version>]
mb tool list [--outdated] | upgrade [--all] <name>... | uninstall [--all] <name>...
mb help | version
```

Every command and subcommand also understands `-h`/`--help` (which wins over
any other argument, as in `uv`). `--bin <dir>` is accepted as an alias for
`--bin-dir <dir>`.

### Toolchains

```bash
mb moon install              # install the latest release
mb moon install 0.10.14      # install the release with moonc 0.10.14
mb moon install nightly      # install the nightly build
mb moon list                 # installed toolchains + the release channel
mb moon default 0.10.14      # select the version ~/.local/bin points at
mb moon which                # print the active moon binary
mb moon uninstall 0.10.14    # remove a toolchain and its ~/.local/bin shims
```

`mb moon list` lists the installed toolchains, then the versions published on
the release channel (`cli.moonbitlang.com/version.json`, i.e. what `latest`
resolves to).

Toolchains live under `$MB_HOME/moon/<version>` and the `moon`, `moonc`,
`moonfmt`, ... binaries are symlinked into `~/.local/bin`. Uninstalling a
toolchain removes those symlinks too (it matches them by target, so nothing is
left dangling), and re-points them at another installed toolchain when one is
available.

Toolchains live under `$MB_HOME/moon/<version>` and the `moon`, `moonc`,
`moonfmt`, ... binaries are symlinked into `~/.local/bin`. Installing a
toolchain also downloads and bundles `core` so that builds work offline.

`mb moon install 0.10.14` resolves a bare compiler version to the full release
key (e.g. `0.10.14+7d59c7ec9`). Pass the full `X.Y.Z+hash` string to pin an
exact build.

### Running

```bash
mb run moon build            # run with the default managed toolchain
mb run --moon 0.10.14 moon test
mb run --moon nightly node script.js
```

`mb run` prepends the selected toolchain's `bin` to `PATH` and points
`MOON_HOME` at it before executing the command. When no managed toolchain is
selected it falls back to the `moon` already on `PATH`.

### Tools

```bash
mb tool install bobzhang/zip         # a mooncakes.io module, latest version
mb tool install bobzhang/zip@0.1.1   # pinned version
mb tool install denoland/deno        # any GitHub repository with releases
mb tool install denoland/deno@2.9.7  # pinned to a release tag
mb tool install https://github.com/BurntSushi/ripgrep
mb tool install author/tool --moon 0.10.14 --bin-dir ~/.local/bin
mb tool list                         # or: mb tool list --outdated
mb tool upgrade author/tool          # one or more names, or --all
mb tool uninstall author/tool        # one or more names, or --all
```

`mb tool install` resolves the name on mooncakes.io first. When the name is a
registered module it prefers a **prebuilt binary from the module's GitHub
release** and only compiles from source when there is none:

1. fetch `mooncakes.io/api/v0/manifest/<author>/<module>` to get the version,
   checksum and `metadata.repository`;
2. if the repository is on GitHub, look for a release asset that matches the
   host OS and CPU architecture. A pinned version is matched against the
   `v<version>` and `<version>` tags; without a pin the repository's latest
   release is used. Assets that are archives (`zip`, `tar`, `tar.gz`/`tgz`,
   `tar.xz`/`txz`, `tar.bz2`, `tar.zst`, bare `gz`/`xz`/`bz2`/`zst`, ...) are
   unpacked and every executable inside is installed; a plain asset is
   installed under a name derived from its filename (so `mb-linux-x86_64`
   becomes `mb`). GitHub's `sha256` digest is verified when present;
3. otherwise fall back to building from source: download
   `https://download.mooncakes.io/user/<author>/<module>/<version>.zip`, verify
   its SHA-256 against the registry checksum, extract it to
   `$MB_HOME/tool/<author>-<module>/<version>/src` and run
   `moon build --target native --release` with a managed (or system) toolchain;
4. copy every executable into `~/.local/bin` (or the `--bin-dir <dir>` given).

A name that is **not** on mooncakes.io is treated as a GitHub repository —
`owner/repo`, `owner/repo@tag` or a full URL — and installed from its releases
the same way. It is recorded under the repository slug and the release tag.

`mb tool list` prints the tools directory (`$MB_HOME/tool`), and for each tool
the directory its binaries were installed into and any that are missing. With
`--outdated` it consults mooncakes.io and marks tools that have a newer version;
a GitHub-only tool is reported as unchecked, since it has no registry entry.
`mb tool uninstall` removes the binaries from that same directory, so a tool
installed with `--bin <dir>`/`--bin-dir <dir>` is cleaned up correctly too.

`mb tool upgrade` takes one or more names (a version specifier is ignored and
the latest version is installed) or `--all` for every installed tool; it always
rebuilds each tool into the directory it was originally installed into. As in
`uv`, an upgrade or uninstall without any name and without `--all` is a usage
error.

## Environment

| Variable         | Meaning                                              | Default             |
| ---------------- | ---------------------------------------------------- | ------------------- |
| `MB_HOME`        | Data directory for toolchains and tools              | `~/.local/share/mb` |
| `MB_BIN_DIR`     | Where executables are installed                      | `~/.local/bin`      |
| `XDG_DATA_HOME` | Used when `MB_HOME` is unset                         | `~/.local/share`    |
| `GITHUB_TOKEN`   | GitHub API token for release lookups (also `GH_TOKEN`) | unset             |

## Layout

```
$MB_HOME/
  moon/<version>/          # a full MoonBit toolchain (bin, lib, lib/core)
  moon/.default            # the selected version
  tool/<author>-<name>/<version>/
    src/                   # extracted mooncakes source
    tool.json              # { name, version, bins, bin }
```

## Releases, CI and npm

- `.github/workflows/ci.yml` runs `moon check`, `moon test` and a native
  release build on Linux and macOS.
- `.github/workflows/release.yml` builds `mb` for `linux-x86_64`,
  `linux-aarch64` and `darwin-aarch64` and attaches the binaries (plus
  `.sha256` checksums) to a GitHub Release when a `v*` tag is pushed:

  ```bash
  git tag v0.1.4 && git push origin v0.1.4
  ```

- `npmjs/` is an npm wrapper. `pnpm install -g @tomasko/mb` downloads the matching
  release asset and exposes the `mb` command. It is published separately to
  npm:

  ```bash
  cd npmjs && npm publish --access public
  ```

- `install.sh` is the `curl | bash` installer:

  ```bash
  curl -LsSf https://raw.githubusercontent.com/tomasky/mb/main/install.sh | bash
  ```

  It detects the platform, downloads `mb-<target>` (plus its `.sha256`) from
  the latest release and installs it into `~/.local/bin`. Options: `--version
  <v>`, `--install-dir <dir>`, `--no-verify`; environment: `MB_VERSION`,
  `MB_INSTALL_DIR`, `MB_REPO`, `MB_DOWNLOAD_BASE`.

  Publishing to mooncakes.io ignores `npmjs/`: `.moonignore` at the
  repository root excludes it (and build/editor junk) from the package that
  `moon publish` uploads.

## Development

```bash
moon check          # type-check
moon test           # run the test suite
moon info && moon fmt
```

The public library API lives in the root package (`kupas/mb`, the mooncakes.io
module name); the CLI entry point is `cmd/mb`. The GitHub repository is
`tomasky/mb`.
