# mb

A MoonBit-native take on [uv](https://github.com/astral-sh/uv): a small,
fast toolchain and package manager for MoonBit, written in MoonBit.

`mb` manages two things, mirroring how `uv python` / `uv run` / `uv tool`
manage Python:

- **MoonBit toolchains** — download, install and switch between compiler
  releases from `cli.moonbitlang.com` (`mb moon ...`).
- **Tools** — download a module from [mooncakes.io](https://mooncakes.io),
  compile it to a native binary and install it (`mb tool ...`).

Everything installs to `~/.local/bin` by default. Only Linux and macOS
(including Apple Silicon) are supported.

## Install

```bash
curl -LsSf https://raw.githubusercontent.com/tomasky/mb/main/install.sh | bash
```

Or with npm:

```bash
npm install -g mb
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
mb tool install <author>/<module>[@<version>] [--force] [--bin <dir>] [--moon <version>]
mb tool list | upgrade [module] | uninstall <module>
mb help | version
```

### Toolchains

```bash
mb moon install              # install the latest release
mb moon install 0.10.14      # install the release with moonc 0.10.14
mb moon install nightly      # install the nightly build
mb moon list                 # installed + available versions
mb moon default 0.10.14      # select the version ~/.local/bin points at
mb moon which                # print the active moon binary
```

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
mb tool install bobzhang/zip         # latest version
mb tool install bobzhang/zip@0.1.1   # pinned version
mb tool install author/tool --moon 0.10.14 --bin ~/.local/bin
mb tool list
mb tool upgrade author/tool
mb tool uninstall author/tool
```

`mb tool install`:

1. resolves the module and version via `mooncakes.io/api/v0/manifest/...`;
2. downloads `https://download.mooncakes.io/user/<author>/<module>/<version>.zip`
   and verifies its SHA-256 against the registry checksum;
3. extracts the source to `$MB_HOME/tool/<author>-<module>/<version>/src`;
4. builds it with a managed (or system) toolchain:
   `moon build --target native --release`;
5. copies every native executable it produced into `~/.local/bin`.

## Environment

| Variable         | Meaning                                              | Default             |
| ---------------- | ---------------------------------------------------- | ------------------- |
| `MB_HOME`        | Data directory for toolchains and tools              | `~/.local/share/mb` |
| `MB_BIN_DIR`     | Where executables are installed                      | `~/.local/bin`      |
| `XDG_DATA_HOME` | Used when `MB_HOME` is unset                         | `~/.local/share`    |

## Layout

```
$MB_HOME/
  moon/<version>/          # a full MoonBit toolchain (bin, lib, lib/core)
  moon/.default            # the selected version
  tool/<author>-<name>/<version>/
    src/                   # extracted mooncakes source
    tool.json              # { name, version, bins }
```

## Releases, CI and npm

- `.github/workflows/ci.yml` runs `moon check`, `moon test` and a native
  release build on Linux and macOS.
- `.github/workflows/release.yml` builds `mb` for `linux-x86_64`,
  `linux-aarch64`, `darwin-aarch64` and `darwin-x86_64` and attaches the
  binaries to a GitHub Release when a `v*` tag is pushed:

  ```bash
  git tag v0.1.1 && git push origin v0.1.1
  ```

- `npmjs/` is an npm wrapper. `npm install -g mb` downloads the matching
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
