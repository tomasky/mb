#!/usr/bin/env node
// Thin launcher for the downloaded native `mb` binary.
"use strict";

const { spawnSync } = require("child_process");
const fs = require("fs");
const path = require("path");

const ext = process.platform === "win32" ? ".exe" : "";
const binary = path.join(__dirname, "mb" + ext);

if (!fs.existsSync(binary)) {
  console.error(
    `mb: native binary not found at ${binary}\n` +
      "mb: reinstall it with `npm rebuild mb` (or `npm install -g mb --force`)."
  );
  process.exit(1);
}

const result = spawnSync(binary, process.argv.slice(2), { stdio: "inherit" });

if (result.error) {
  console.error(`mb: failed to launch ${binary}: ${result.error.message}`);
  process.exit(1);
}

process.exit(typeof result.status === "number" ? result.status : 1);
