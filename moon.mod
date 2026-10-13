// Learn more about moon.mod configuration:
// https://docs.moonbitlang.com/en/latest/toolchain/moon/module.html
//
// To add a dependency, run this command in your terminal:
//   moon add moonbitlang/x
//
// Or manually declare it in `import`, for example:
// import {
//   "moonbitlang/x@0.4.6",
// }

name = "kupas/mb"

version = "0.1.6"

readme = "README.mbt.md"

repository = "https://github.com/tomasky/mb"

license = "Apache-2.0"

keywords = [ "moonbit", "package-manager", "toolchain", "cli", "uv" ]

preferred_target = "native"

description = "A MoonBit-native, uv-style toolchain and package manager: manage MoonBit toolchains and install tools from mooncakes.io and github."

import {
  "moonbitlang/x@0.5.5",
  "bobzhang/zip@0.1.1",
}
