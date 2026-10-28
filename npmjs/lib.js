"use strict";

// Shared install logic for the npm wrapper.
//
// Downloaded binaries live in a per-user cache (`$XDG_CACHE_HOME/mb/npm`, or
// `~/.cache/mb/npm`) so that a package version whose GitHub release has not
// been published yet can fall back to the previous binary, and so old binaries
// can be pruned. Only the two newest versions are kept.
//
// Overridable:
//   MB_REPO            owner/repo            (default: parsed from package.json)
//   MB_VERSION         release version       (default: package.json version)
//   MB_DOWNLOAD_BASE   full base URL         (overrides MB_REPO/MB_VERSION)
//   MB_CACHE_DIR       cache directory       (default: ~/.cache/mb/npm)
//   MB_FORCE_DOWNLOAD  re-download even if the binary is present
//   MB_SKIP_DOWNLOAD   never download

const fs = require("fs");
const os = require("os");
const path = require("path");
const https = require("https");
const http = require("http");

const pkg = require("./package.json");

// Node `platform-arch` -> MoonBit release target. Intel macOS is absent on
// purpose: the MoonBit toolchain no longer ships a darwin-x86_64 target.
const TARGETS = {
  "linux-x64": "linux-x86_64",
  "linux-arm64": "linux-aarch64",
  "darwin-arm64": "darwin-aarch64",
};

// How many downloaded versions to keep in the cache (current + previous).
const KEEP_VERSIONS = 2;

function repoSlug(repo) {
  if (!repo) return null;
  const url = typeof repo === "string" ? repo : repo.url || "";
  const m = url.match(/github\.com[/:]([^/]+)\/([^/.]+)/);
  return m ? `${m[1]}/${m[2]}` : null;
}

function repoName() {
  return process.env.MB_REPO || repoSlug(pkg.repository) || "tomasky/mb";
}

function targetName() {
  return TARGETS[`${process.platform}-${process.arch}`];
}

function assetName(target) {
  return `mb-${target}`;
}

// --- binary cache ----------------------------------------------------------

function cacheDir() {
  if (process.env.MB_CACHE_DIR) return process.env.MB_CACHE_DIR;
  const base = process.env.XDG_CACHE_HOME || path.join(os.homedir(), ".cache");
  return path.join(base, "mb", "npm");
}

function cachedBinary(version, target) {
  return path.join(cacheDir(), `${assetName(target)}-${version}`);
}

function compareVersions(a, b) {
  const pa = String(a).split(/[.+-]/);
  const pb = String(b).split(/[.+-]/);
  for (let i = 0; i < Math.max(pa.length, pb.length); i++) {
    const x = parseInt(pa[i], 10) || 0;
    const y = parseInt(pb[i], 10) || 0;
    if (x !== y) return x - y;
  }
  return 0;
}

// Cached binaries for `target`, newest version first.
function listCached(target) {
  let names;
  try {
    names = fs.readdirSync(cacheDir());
  } catch {
    return [];
  }
  const prefix = `${assetName(target)}-`;
  const out = [];
  for (const name of names) {
    if (!name.startsWith(prefix)) continue;
    const version = name.slice(prefix.length);
    if (!/^\d+\.\d+\.\d+/.test(version)) continue;
    out.push({ version, path: path.join(cacheDir(), name) });
  }
  return out.sort((a, b) => compareVersions(b.version, a.version));
}

function newestCached(target) {
  return listCached(target)[0] || null;
}

// Keep only the newest `keep` versions; delete the rest.
function pruneCache(target, keep = KEEP_VERSIONS) {
  for (const entry of listCached(target).slice(keep)) {
    try {
      fs.rmSync(entry.path, { force: true });
    } catch {
      // best-effort
    }
  }
}

function versionFromUrl(url) {
  const m = String(url).match(/\/releases\/download\/v?([^/]+)\//);
  return m ? m[1] : null;
}

function binaryPath() {
  return path.join(
    __dirname,
    "bin",
    process.platform === "win32" ? "mb.exe" : "mb"
  );
}

function isInstalled() {
  try {
    fs.accessSync(binaryPath(), fs.constants.X_OK);
    return true;
  } catch {
    return false;
  }
}

// --- downloading ------------------------------------------------------------

// Candidates to try, in order. The first one pins the package version; when it
// is missing (the GitHub release was not published), fall back to the latest
// published release and use it *as-is*. The version recorded for the fallback
// comes from the redirect URL, so a 0.1.4 binary is never stored as 0.1.5.
function candidateUrls(target) {
  const asset = assetName(target);
  if (process.env.MB_DOWNLOAD_BASE) {
    return [
      {
        url: `${process.env.MB_DOWNLOAD_BASE.replace(/\/$/, "")}/${asset}`,
        version: process.env.MB_VERSION || pkg.version,
      },
    ];
  }
  const repo = repoName();
  if (process.env.MB_VERSION) {
    return [
      {
        url: `https://github.com/${repo}/releases/download/v${process.env.MB_VERSION}/${asset}`,
        version: process.env.MB_VERSION,
      },
    ];
  }
  return [
    {
      url: `https://github.com/${repo}/releases/download/v${pkg.version}/${asset}`,
      version: pkg.version,
    },
    {
      url: `https://github.com/${repo}/releases/latest/download/${asset}`,
      version: null,
    },
  ];
}

function downloadUrl(target) {
  return candidateUrls(target)[0].url;
}

// `releaseUrl` is the first URL in the redirect chain that names a release tag,
// e.g. `.../releases/download/v0.1.9/mb-linux-x86_64`. It is preserved across
// the redirect to the asset CDN so the caller can record the real version.
function fetch(url, redirects, releaseUrl) {
  return new Promise((resolve, reject) => {
    if (redirects > 10) return reject(new Error("too many redirects"));
    const client = url.startsWith("http:") ? http : https;
    const req = client.get(
      url,
      { headers: { "user-agent": `mb-npm/${pkg.version}` } },
      (res) => {
        const { statusCode, headers } = res;
        const known = releaseUrl || (versionFromUrl(url) ? url : null);
        if (statusCode >= 300 && statusCode < 400 && headers.location) {
          res.resume();
          const next = new URL(headers.location, url).toString();
          resolve(fetch(next, redirects + 1, known));
          return;
        }
        if (statusCode !== 200) {
          res.resume();
          reject(new Error(`GET ${url} -> HTTP ${statusCode}`));
          return;
        }
        resolve({ res, url, releaseUrl: known });
      }
    );
    req.on("error", reject);
  });
}

function writeBody(res, dest) {
  fs.mkdirSync(path.dirname(dest), { recursive: true });
  const tmp = `${dest}.tmp`;
  return new Promise((resolve, reject) => {
    const out = fs.createWriteStream(tmp);
    res.pipe(out);
    out.on("finish", () =>
      out.close(() => {
        try {
          fs.renameSync(tmp, dest);
          fs.chmodSync(dest, 0o755);
          resolve();
        } catch (err) {
          reject(err);
        }
      })
    );
    out.on("error", reject);
    res.on("error", reject);
  });
}

// Download into the cache, returning `{ path, version }`.
async function download(target, log) {
  let lastError;
  for (const candidate of candidateUrls(target)) {
    try {
      log(`mb: downloading ${candidate.url}`);
      const { res, url, releaseUrl } = await fetch(candidate.url, 0);
      const version =
        candidate.version ||
        versionFromUrl(releaseUrl || url) ||
        pkg.version;
      const dest = cachedBinary(version, target);
      await writeBody(res, dest);
      return { path: dest, version };
    } catch (err) {
      lastError = err;
      if (!/HTTP 404/.test(err.message)) throw err;
      log(`mb: ${candidate.url} is not available; trying the next source`);
    }
  }
  throw lastError;
}

function linkBinary(targetPath) {
  const dest = binaryPath();
  fs.mkdirSync(path.dirname(dest), { recursive: true });
  try {
    fs.rmSync(dest, { force: true });
  } catch {
    // ignore
  }
  try {
    fs.symlinkSync(targetPath, dest);
  } catch {
    fs.copyFileSync(targetPath, dest);
    fs.chmodSync(dest, 0o755);
  }
}

// Resolves to a ready-to-run binary path, downloading it when missing.
async function ensureBinary({ force = false, log = () => {} } = {}) {
  const installed = binaryPath();

  if (!force && !process.env.MB_FORCE_DOWNLOAD && isInstalled()) {
    return installed;
  }

  const target = targetName();
  if (!target) {
    throw new Error(
      `unsupported platform ${process.platform}-${process.arch}; mb ` +
        `supports linux-x64, linux-arm64 and darwin-arm64 (the MoonBit ` +
        `toolchain no longer ships a darwin-x64 target)`
    );
  }

  if (process.env.MB_SKIP_DOWNLOAD) {
    if (isInstalled()) return installed;
    const newest = newestCached(target);
    if (newest) {
      linkBinary(newest.path);
      return installed;
    }
    throw new Error("MB_SKIP_DOWNLOAD is set but no binary is cached");
  }

  let chosen;
  try {
    chosen = await download(target, log);
  } catch (err) {
    // The exact version may be unpublished and the network may be down; use
    // the newest previously-downloaded binary rather than failing.
    const newest = newestCached(target);
    if (newest) {
      log(`mb: could not install a binary (${err.message}); using cached v${newest.version}`);
      chosen = newest;
    } else {
      throw err;
    }
  }

  linkBinary(chosen.path);
  pruneCache(target);
  log(`mb: using mb v${chosen.version} (${chosen.path})`);
  return installed;
}

module.exports = {
  pkg,
  TARGETS,
  targetName,
  downloadUrl,
  binaryPath,
  isInstalled,
  cacheDir,
  listCached,
  pruneCache,
  ensureBinary,
};
