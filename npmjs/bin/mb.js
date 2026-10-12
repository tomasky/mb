#!/usr/bin/env node
// Launcher for the native `mb` binary. Downloads it on first run if the
// postinstall step did not (e.g. `--ignore-scripts`), then forwards all
// arguments, stdio and the exit code.
"use strict";

const { spawnSync } = require("child_process");
const { ensureBinary, pkg } = require("../lib");

async function main() {
  let binary;
  try {
    binary = await ensureBinary({
      log: (line) => process.stderr.write(line + "\n"),
    });
  } catch (err) {
    console.error(`mb: ${err.message}`);
    console.error(
      `mb: run \`npm rebuild ${pkg.name}\` to retry, or set MB_DOWNLOAD_BASE ` +
        `(or MB_REPO/MB_VERSION) to a mirror.`
    );
    process.exit(1);
  }

  const result = spawnSync(binary, process.argv.slice(2), { stdio: "inherit" });

  if (result.error) {
    console.error(`mb: failed to launch ${binary}: ${result.error.message}`);
    process.exit(1);
  }

  process.exit(typeof result.status === "number" ? result.status : 1);
}

main();
