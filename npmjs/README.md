# mb (npm)

npm wrapper for [`mb`](../../blob/main/README.mbt.md) — a MoonBit-native, uv-style toolchain
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
Releases into a per-user cache and links it at `bin/mb`. The published `bin`
entry (`bin/mb.js`) then spawns it, forwarding arguments, standard IO and the
exit code.

The postinstall download is best-effort, and the launcher downloads the
binary on first run if it is missing (for example when installing with
`--ignore-scripts`, or when the release was not available yet).

### Version fallback and cache pruning

Binaries are cached under `$XDG_CACHE_HOME/mb/npm` (usually
`~/.cache/mb/npm`), one file per version. If the GitHub release matching the
npm package version has not been published yet, the wrapper falls back to the
latest published release and records it under its **real** tag, so a `0.1.4`
binary is never relabelled as `0.1.5`. The binary is used as-is and `mb
--version` reports `0.1.4`.

Each successful install prunes the cache to the **two newest** versions: after
installing `0.1.5`, a cached `0.1.3` is deleted while `0.1.4` is kept as the
previous fallback.

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

## Install scripts are blocked by default

Recent npm (12+) and pnpm (10+) versions do **not** run a dependency's install
scripts unless the package is approved, so `postinstall` is skipped and
`bin/mb` is missing right after install:

```
npm warn install-scripts 1 package had install scripts blocked because they are not covered by allowScripts:
npm warn install-scripts   @tomasko/mb@0.2.0 (postinstall: node install.js)
mb: native binary not found at .../node_modules/@tomasko/mb/bin/mb
```

Nothing is broken: `bin/mb.js` downloads the binary on first run. To have it
downloaded at install time instead, approve the build once:

```bash
npm install-scripts approve @tomasko/mb   # npm 12+ (writes `allowScripts`)
pnpm approve-builds                       # pnpm 10+
```

Either way, re-run the download manually with:

```bash
npm rebuild @tomasko/mb
# or
pnpm rebuild @tomasko/mb
```

## Overrides

| Variable             | Purpose                                          |
| -------------------- | ------------------------------------------------ |
| `MB_REPO`            | `owner/repo` to download from                    |
| `MB_VERSION`         | release version to download                      |
| `MB_DOWNLOAD_BASE`   | full base URL (mirror), e.g. `https://host/assets` |
| `MB_CACHE_DIR`       | binary cache directory (default: `~/.cache/mb/npm`) |
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
