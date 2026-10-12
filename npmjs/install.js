#!/usr/bin/env node
// Postinstall hook: download the prebuilt `mb` binary for this platform.
//
// This is best-effort: if the download fails the install still succeeds, and
// `bin/mb.js` retries on first run. Set MB_SKIP_DOWNLOAD=1 to opt out.
"use strict";

const { ensureBinary, pkg } = require("./lib");

if (process.env.MB_SKIP_DOWNLOAD) {
  console.log("mb: MB_SKIP_DOWNLOAD set, skipping binary download");
  process.exit(0);
}

ensureBinary({ log: console.log })
  .then(() => process.exit(0))
  .catch((err) => {
    console.warn(`mb: could not download the native binary: ${err.message}`);
    console.warn(
      `mb: it will be downloaded on first run instead. If that also fails, ` +
        `set MB_DOWNLOAD_BASE (or MB_REPO/MB_VERSION) to a mirror and run ` +
        `\`npm rebuild ${pkg.name}\`.`
    );
    process.exit(0);
  });
