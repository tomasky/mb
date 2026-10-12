"use strict";

// Shared install logic for the npm wrapper: works out which prebuilt `mb`
// binary to use and downloads it from GitHub Releases on demand.
//
// Overridable for forks / private mirrors:
//   MB_REPO            owner/repo            (default: parsed from package.json)
//   MB_VERSION         release version       (default: package.json version)
//   MB_DOWNLOAD_BASE   full base URL         (overrides MB_REPO/MB_VERSION)
//   MB_FORCE_DOWNLOAD  re-download even if the binary is present
//   MB_SKIP_DOWNLOAD   never download

const fs = require("fs");
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

function repoSlug(repo) {
  if (!repo) return null;
  const url = typeof repo === "string" ? repo : repo.url || "";
  const m = url.match(/github\.com[/:]([^/]+)\/([^/.]+)/);
  return m ? `${m[1]}/${m[2]}` : null;
}

function targetName() {
  return TARGETS[`${process.platform}-${process.arch}`];
}

function downloadUrl(target) {
  if (process.env.MB_DOWNLOAD_BASE) {
    return `${process.env.MB_DOWNLOAD_BASE.replace(/\/$/, "")}/mb-${target}`;
  }
  const repo = process.env.MB_REPO || repoSlug(pkg.repository) || "tomasky/mb";
  const version = process.env.MB_VERSION || pkg.version;
  return `https://github.com/${repo}/releases/download/v${version}/mb-${target}`;
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

function fetch(url, redirects) {
  return new Promise((resolve, reject) => {
    if (redirects > 10) return reject(new Error("too many redirects"));
    const client = url.startsWith("http:") ? http : https;
    const req = client.get(
      url,
      { headers: { "user-agent": `mb-npm/${pkg.version}` } },
      (res) => {
        const { statusCode, headers } = res;
        if (statusCode >= 300 && statusCode < 400 && headers.location) {
          res.resume();
          const next = new URL(headers.location, url).toString();
          resolve(fetch(next, (redirects || 0) + 1));
          return;
        }
        if (statusCode !== 200) {
          res.resume();
          reject(new Error(`GET ${url} -> HTTP ${statusCode}`));
          return;
        }
        resolve(res);
      }
    );
    req.on("error", reject);
  });
}

async function download(target, dest) {
  const url = downloadUrl(target);
  const res = await fetch(url, 0);
  fs.mkdirSync(path.dirname(dest), { recursive: true });
  await new Promise((resolve, reject) => {
    const out = fs.createWriteStream(dest);
    res.pipe(out);
    out.on("finish", () => out.close(resolve));
    out.on("error", reject);
    res.on("error", reject);
  });
  fs.chmodSync(dest, 0o755);
  return url;
}

// Resolves to a ready-to-run binary path, downloading it when missing.
async function ensureBinary({ force = false, log = () => {} } = {}) {
  const dest = binaryPath();

  if (!force && !process.env.MB_FORCE_DOWNLOAD && isInstalled()) {
    return dest;
  }

  if (process.env.MB_SKIP_DOWNLOAD) {
    if (isInstalled()) return dest;
    throw new Error("MB_SKIP_DOWNLOAD is set but no binary is installed");
  }

  const target = targetName();
  if (!target) {
    throw new Error(
      `unsupported platform ${process.platform}-${process.arch}; mb ` +
        `supports linux-x64, linux-arm64 and darwin-arm64 (the MoonBit ` +
        `toolchain no longer ships a darwin-x64 target)`
    );
  }

  log(`mb: downloading ${downloadUrl(target)}`);
  await download(target, dest);
  log(`mb: installed ${dest}`);
  return dest;
}

module.exports = {
  pkg,
  TARGETS,
  targetName,
  downloadUrl,
  binaryPath,
  isInstalled,
  ensureBinary,
};
