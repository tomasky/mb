# mb (npm)

npm wrapper for [`mb`](../../README.md) — a MoonBit-native, uv-style toolchain
and package manager.

```bash
pnpm install -g @tomasko/mb
mb --help
mb moon install 0.10.14
mb tool install bobzhang/zip
```

## How it works

The package itself contains only a small launcher. On install, `install.js`
downloads the prebuilt `mb` binary for the current platform from GitHub
Releases and writes it to `bin/mb`. The published `bin` entry (`bin/mb.js`)
then spawns it, forwarding arguments, standard IO and the exit code.

The postinstall download is best-effort, and the launcher downloads the
binary on first run if it is missing (for example when installing with
`--ignore-scripts`, or when the release was not available yet).

Supported targets:

| Node `platform-arch` | Release asset       |
| -------------------- | ------------------- |
| `linux-x64`          | `mb-linux-x86_64`   |
| `linux-arm64`        | `mb-linux-aarch64`  |
| `darwin-arm64`       | `mb-darwin-aarch64` |

Intel macOS (`darwin-x64`) is not supported: the MoonBit toolchain no longer
ships a `darwin-x86_64` target, so no such build can be produced.

Assets are produced by `.github/workflows/release.yml` when a `v*` tag is
pushed.

## pnpm

pnpm 10+ does **not** run a dependency's install scripts unless the package is
approved, so `postinstall` is skipped and `bin/mb` is missing right after
install. Nothing breaks: `bin/mb.js` downloads the binary on first run.

To have it downloaded at install time instead, approve the build once:

```bash
pnpm approve-builds
# or, in the consuming project's package.json:
#   "pnpm": { "onlyBuiltDependencies": ["@tomasko/mb"] }
```

Either way, `pnpm rebuild @tomasko/mb` re-runs the download.

## Overrides

| Variable             | Purpose                                          |
| -------------------- | ------------------------------------------------ |
| `MB_REPO`            | `owner/repo` to download from                    |
| `MB_VERSION`         | release version to download                      |
| `MB_DOWNLOAD_BASE`   | full base URL (mirror), e.g. `https://host/assets` |
| `MB_FORCE_DOWNLOAD`  | re-download even if the binary is present        |
| `MB_SKIP_DOWNLOAD`   | skip the download entirely                       |

## Publishing

From this directory:

```bash
npm publish --access public
# or
pnpm publish --access public
```

`--access public` is required for scoped packages such as `@tomasko/mb`.
Change `name`, `repository` and `homepage` in `package.json` first if you
publish under a different scope or repository.
