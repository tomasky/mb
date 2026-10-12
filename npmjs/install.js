#!/usr/bin/env node
// Downloads the prebuilt `mb` binary for the current platform from GitHub
// Releases and drops it next to this package's launcher (`bin/mb.js`).
//
// Overridable for forks / private mirrors:
//   MB_REPO            owner/repo            (default: parsed from package.json)
//   MB_VERSION         release version       (default: package.json version)
//   MB_DOWNLOAD_BASE   full base URL         (overrides MB_REPO/MB_VERSION)
//   MB_SKIP_DOWNLOAD   set to skip fetching
"use strict";

const fs = require("fs");
const path = require("path");
const https = require("https");
const http = require("http");

const pkg = require("./package.json");

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

function target() {
  return TARGETS[`${process.platform}-${process.arch}`];
}

function downloadUrl(targetName) {
  if (process.env.MB_DOWNLOAD_BASE) {
    return `${process.env.MB_DOWNLOAD_BASE.replace(/\/$/, "")}/mb-${targetName}`;
  }
  const repo = process.env.MB_REPO || repoSlug(pkg.repository) || "tomasky/mb";
  const version = process.env.MB_VERSION || pkg.version;
  return `https://github.com/${repo}/releases/download/v${version}/mb-${targetName}`;
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

async function main() {
  if (process.env.MB_SKIP_DOWNLOAD) {
    console.log("mb: MB_SKIP_DOWNLOAD set, skipping binary download");
    return;
  }

  const targetName = target();
  if (!targetName) {
    throw new Error(
      `unsupported platform ${process.platform}-${process.arch}; mb ` +
        `supports linux-x64, linux-arm64 and darwin-arm64 (the MoonBit ` +
        `toolchain no longer ships a darwin-x64 target)`
    );
  }

  const ext = process.platform === "win32" ? ".exe" : "";
  const dest = path.join(__dirname, "bin", "mb" + ext);
  fs.mkdirSync(path.dirname(dest), { recursive: true });

  if (fs.existsSync(dest) && !process.env.MB_FORCE_DOWNLOAD) {
    console.log(`mb: ${dest} already present, skipping download`);
    return;
  }

  const url = downloadUrl(targetName);
  console.log(`mb: downloading ${url}`);
  const res = await fetch(url, 0);
  await new Promise((resolve, reject) => {
    const out = fs.createWriteStream(dest);
    res.pipe(out);
    out.on("finish", () => out.close(resolve));
    out.on("error", reject);
    res.on("error", reject);
  });
  fs.chmodSync(dest, 0o755);
  console.log(`mb: installed ${dest}`);
}

main().catch((err) => {
  console.error(`mb: failed to install the native binary: ${err.message}`);
  console.error(
    "mb: set MB_DOWNLOAD_BASE (or MB_REPO/MB_VERSION) to point at a mirror, " +
      "or set MB_SKIP_DOWNLOAD=1 to skip."
  );
  process.exit(1);
});
