// Whitebox tests for the prebuilt-release helpers.

///|
test "parse_github_repo" {
  assert_eq(
    parse_github_repo("https://github.com/tomasky/mb"),
    Some("tomasky/mb"),
  )
  assert_eq(
    parse_github_repo("https://github.com/tomasky/mb.git"),
    Some("tomasky/mb"),
  )
  assert_eq(
    parse_github_repo("https://github.com/tomasky/mb/"),
    Some("tomasky/mb"),
  )
  assert_eq(
    parse_github_repo("git@github.com:tomasky/mb.git"),
    Some("tomasky/mb"),
  )
  assert_eq(parse_github_repo("http://github.com/a/b/tree/main"), Some("a/b"))
  assert_eq(parse_github_repo("https://gitlab.com/a/b"), None)
  assert_eq(parse_github_repo(""), None)
  assert_eq(parse_github_repo("https://github.com/a"), None)
  // A bare slug is how a package that is not on mooncakes.io is named.
  assert_eq(parse_github_repo("denoland/deno"), Some("denoland/deno"))
  assert_eq(parse_github_repo("gitlab.com/a/b"), None)
}

///|
test "parse_github_spec" {
  assert_eq(
    parse_github_spec("denoland/deno@2.9.7"),
    Some(("denoland/deno", Some("2.9.7"))),
  )
  assert_eq(parse_github_spec("denoland/deno"), Some(("denoland/deno", None)))
  assert_eq(
    parse_github_spec("https://github.com/denoland/deno"),
    Some(("denoland/deno", None)),
  )
  assert_eq(
    parse_github_spec("https://github.com/denoland/deno@v2.9.7"),
    Some(("denoland/deno", Some("v2.9.7"))),
  )
  // The `@` of a git remote must not be read as a version separator.
  assert_eq(
    parse_github_spec("git@github.com:denoland/deno.git"),
    Some(("denoland/deno", None)),
  )
  assert_eq(parse_github_spec("not a repo"), None)
}

///|
test "asset_matches_platform" {
  assert_true(asset_matches_platform("tool-linux-x86_64", "linux-x86_64"))
  assert_true(asset_matches_platform("tool-linux-amd64.tar.gz", "linux-x86_64"))
  assert_true(asset_matches_platform("tool-Darwin-arm64", "darwin-aarch64"))
  assert_true(asset_matches_platform("tool-macos-aarch64", "darwin-aarch64"))
  assert_false(asset_matches_platform("tool-linux-aarch64", "linux-x86_64"))
  // Both an OS and an architecture token are required.
  assert_false(asset_matches_platform("tool-linux", "linux-x86_64"))
  assert_false(asset_matches_platform("tool-x86_64", "linux-x86_64"))
}

///|
test "asset filters" {
  assert_true(asset_is_checksum("mb-linux-x86_64.sha256"))
  assert_false(asset_is_checksum("mb-linux-x86_64"))
  assert_false(is_installable_asset("tool-linux-x86_64.sha256"))
  assert_false(is_installable_asset("tool-windows-x86_64.exe"))
  assert_false(is_installable_asset("tool-linux-x86_64.deb"))
  assert_true(is_installable_asset("tool-linux-x86_64.tar.gz"))
}

///|
test "archive names" {
  assert_true(is_archive_name("a.tar.gz"))
  assert_true(is_archive_name("a.tgz"))
  assert_true(is_archive_name("a.zip"))
  assert_true(is_archive_name("a.xz"))
  assert_true(is_archive_name("a.tar"))
  // No suffix means the asset is a plain, uncompressed file.
  assert_false(is_archive_name("mb-linux-x86_64"))
  assert_eq(strip_archive_ext("a.tar.gz"), Some("a"))
  assert_eq(strip_archive_ext("a.gz"), Some("a"))
  assert_eq(strip_archive_ext("a"), None)
}

///|
test "binary_name_from_asset" {
  assert_eq(binary_name_from_asset("mb-linux-x86_64"), "mb")
  assert_eq(binary_name_from_asset("mytool-v1.2.3-linux-amd64"), "mytool")
  assert_eq(binary_name_from_asset("tool-darwin-arm64"), "tool")
  assert_eq(binary_name_from_asset("tool-linux-x86_64.tar.gz"), "tool")
  // Nothing but platform tokens: the caller falls back to the module name.
  assert_eq(binary_name_from_asset("linux-x86_64"), "")
}

///|
test "is_library_name" {
  assert_true(is_library_name("libfoo.so"))
  assert_true(is_library_name("libfoo.so.1"))
  assert_true(is_library_name("foo.dylib"))
  assert_true(is_library_name("foo.a"))
  assert_false(is_library_name("mytool"))
}

///|
test "pick_release_asset" {
  let j = @json.parse(
    "{\"assets\":[{\"name\":\"tool-linux-x86_64.sha256\",\"browser_download_url\":\"u1\"},{\"name\":\"tool-darwin-aarch64\",\"browser_download_url\":\"u2\"},{\"name\":\"tool-linux-x86_64.tar.gz\",\"browser_download_url\":\"u3\",\"digest\":\"sha256:abc\"}]}",
  )
  let (name, url, digest) = pick_release_asset(j, "linux-x86_64").unwrap()
  assert_eq(name, "tool-linux-x86_64.tar.gz")
  assert_eq(url, "u3")
  assert_eq(digest, Some("sha256:abc"))
  // Without an archive the raw binary is chosen.
  let j2 = @json.parse(
    "{\"assets\":[{\"name\":\"tool-linux-x86_64\",\"browser_download_url\":\"u4\"}]}",
  )
  let (n2, u2, d2) = pick_release_asset(j2, "linux-x86_64").unwrap()
  assert_eq(n2, "tool-linux-x86_64")
  assert_eq(u2, "u4")
  assert_eq(d2, None)
  // No matching platform: nothing is picked.
  assert_true(pick_release_asset(j, "darwin-x86_64") is None)
}

///|
test "sha256_of_digest" {
  assert_eq(sha256_of_digest("sha256:AbC"), Some("abc"))
  assert_eq(sha256_of_digest("md5:abc"), None)
}

///|
test "extract_archive tar.gz" {
  let src = temp_path() + ".d"
  mkdir_p(src)
  write_text(path_join(src, "hello.txt"), "hi")
  let tgz = temp_path() + ".tar.gz"
  assert_true(
    run_ok(
      "tar -czf " + shell_quote(tgz) + " -C " + shell_quote(src) + " hello.txt",
    ),
  )
  let out = temp_path() + ".d"
  extract_archive(tgz, "hello.tar.gz", out)
  assert_true(file_exists(path_join(out, "hello.txt")))
  rm_rf(src)
  rm_rf(tgz)
  rm_rf(out)
}

///|
test "collect_executables from an archive" {
  let src = temp_path() + ".d"
  mkdir_p(src)
  // `/bin/sh` is an ELF on Linux and a Mach-O on macOS, so it exercises the
  // same detection the real release assets go through.
  assert_true(run_ok("cp /bin/sh " + shell_quote(path_join(src, "mytool"))))
  let tgz = temp_path() + ".tar.gz"
  assert_true(
    run_ok("tar -czf " + shell_quote(tgz) + " -C " + shell_quote(src) + " ."),
  )
  let out = temp_path() + ".d"
  extract_archive(tgz, "tool-linux-x86_64.tar.gz", out)
  let bins = collect_executables(out)
  assert_eq(bins.length(), 1)
  assert_eq(bins[0].0, "mytool")
  rm_rf(src)
  rm_rf(tgz)
  rm_rf(out)
}

///|
test "extract_archive bare gz" {
  let src = temp_path()
  write_text(src, "hello")
  let gz = temp_path() + ".gz"
  assert_true(run_ok("gzip -c " + shell_quote(src) + " > " + shell_quote(gz)))
  let out = temp_path() + ".d"
  extract_archive(gz, "tool.gz", out)
  assert_eq(read_text(path_join(out, "tool")), "hello")
  rm_rf(src)
  rm_rf(gz)
  rm_rf(out)
}
