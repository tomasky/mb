// Whitebox tests for internal helpers.

///|
test "path_join" {
  assert_eq(path_join("a", "b"), "a/b")
  assert_eq(path_join("a/", "b"), "a/b")
  assert_eq(path_join("", "b"), "b")
  assert_eq(path_join("/x", "y/z"), "/x/y/z")
}

///|
test "path_join_all" {
  assert_eq(path_join_all(["a", "b", "c"]), "a/b/c")
  assert_eq(path_join_all(["/root", ".local", "bin"]), "/root/.local/bin")
}

///|
test "parent_dir and base_name" {
  assert_eq(parent_dir("/a/b/c"), "/a/b")
  assert_eq(parent_dir("/a"), "/")
  assert_eq(parent_dir("a"), "")
  assert_eq(base_name("/a/b/c"), "c")
  assert_eq(base_name("c"), "c")
}

///|
test "shell_quote" {
  assert_eq(shell_quote("abc"), "'abc'")
  assert_eq(shell_quote("a b"), "'a b'")
  assert_eq(shell_quote("it's"), "'it'\\''s'")
}

///|
test "sha256_hex" {
  assert_eq(
    sha256_hex(@utf8.encode("abc")),
    "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad",
  )
}

///|
test "urlencode_plus" {
  assert_eq(urlencode_plus("0.10.14+7d59c7ec9"), "0.10.14%2B7d59c7ec9")
  assert_eq(urlencode_plus("latest"), "latest")
}

///|
test "parse_version_items" {
  let j = @json.parse(
    "{\"items\":[{\"name\":\"moon\",\"version\":\"0.1.20260920 (914d7da 2026-09-20)\"},{\"name\":\"moonc\",\"version\":\"v0.10.14+7d59c7ec9 (2026-09-18)\"},{\"name\":\"moonrun\",\"version\":\"moonrun 0.1.20260920 (914d7da 2026-09-20)\"}]}",
  )
  let items = parse_version_items(j)
  assert_eq(items.length(), 3)
  assert_eq(items[0], ("moon", "0.1.20260920"))
  assert_eq(items[1], ("moonc", "v0.10.14+7d59c7ec9"))
  // The tool name may be repeated in the version string.
  assert_eq(items[2], ("moonrun", "0.1.20260920"))
}

///|
test "resolve_moon_spec explicit" {
  let s = resolve_moon_spec("0.10.14+abc123")
  assert_eq(s.download_key, "0.10.14+abc123")
  assert_eq(s.store_name, "0.10.14+abc123")
  let n = resolve_moon_spec("nightly")
  assert_eq(n.download_key, "nightly")
  assert_eq(n.store_name, "nightly")
}

///|
test "split_spec" {
  let (m, v) = split_spec("author/mod@1.2.3")
  assert_eq(m, "author/mod")
  assert_eq(v, Some("1.2.3"))
  let (m2, v2) = split_spec("author/mod")
  assert_eq(m2, "author/mod")
  assert_eq(v2, None)
}

///|
test "json accessors" {
  let j = @json.parse("{\"a\":\"x\",\"b\":[1,2],\"c\":{\"d\":true}}")
  assert_eq(json_string(j, "a"), Some("x"))
  assert_eq(json_array(j, "b").map(a => a.length()), Some(2))
  assert_eq(json_bool(json_object(j, "c").unwrap(), "d"), Some(true))
  assert_eq(json_string(j, "missing"), None)
}

///|
test "parse_version_flags" {
  let (v, f) = parse_version_flags(["0.10.14", "--force"], "latest").unwrap()
  assert_eq(v, "0.10.14")
  assert_true(f)
  let (v2, f2) = parse_version_flags([], "latest").unwrap()
  assert_eq(v2, "latest")
  assert_false(f2)
  assert_true(parse_version_flags(["--bogus"], "latest") is Err(_))
}

///|
test "parse_tool_install_flags" {
  let o = parse_tool_install_flags([
    "bobzhang/zip@0.1.1", "--bin-dir", "/tmp/b", "--moon=latest", "--force",
  ]).unwrap()
  assert_eq(o.spec, "bobzhang/zip@0.1.1")
  assert_eq(o.bin, "/tmp/b")
  assert_eq(o.moon, "latest")
  assert_true(o.force)
  // The old --bin spelling still works.
  let o2 = parse_tool_install_flags(["a/b", "--bin=/tmp/c"]).unwrap()
  assert_eq(o2.bin, "/tmp/c")
  // Exactly one package is accepted, and it is required.
  assert_true(parse_tool_install_flags([]) is Err(_))
  assert_true(parse_tool_install_flags(["a/b", "c/d"]) is Err(_))
  assert_true(parse_tool_install_flags(["a/b", "--bogus"]) is Err(_))
}

///|
test "parse_names_flags" {
  let o = parse_names_flags([
    "author/tool", "b@1.0.0", "--all", "--moon", "0.10.14",
  ]).unwrap()
  assert_eq(o.names, ["author/tool", "b@1.0.0"])
  assert_true(o.all)
  assert_eq(o.moon, "0.10.14")
  // uv requires names or --all.
  assert_true(parse_names_flags([]) is Err(_))
  assert_true(parse_names_flags(["--moon", "1"]) is Err(_))
  assert_true(parse_names_flags(["a", "--bogus"]) is Err(_))
}

///|
test "parse_list_flags" {
  assert_false(parse_list_flags([]).unwrap())
  assert_true(parse_list_flags(["--outdated"]).unwrap())
  assert_true(parse_list_flags(["--outdated", "x"]) is Err(_))
}

///|
test "parse_required_arg" {
  assert_eq(parse_required_arg(["0.10.14"], "<VERSION>").unwrap(), "0.10.14")
  assert_true(parse_required_arg([], "<VERSION>") is Err(_))
  assert_true(parse_required_arg(["a", "b"], "<VERSION>") is Err(_))
}

///|
test "strip_v and pad_right" {
  assert_eq(strip_v("v0.10.15+943464bfa"), "0.10.15+943464bfa")
  assert_eq(strip_v("0.1.20261012"), "0.1.20261012")
  assert_eq(pad_right("moon", 7), "moon   ")
  assert_eq(pad_right("moonrun", 7), "moonrun")
}

///|
test "shim_points_into" {
  assert_true(shim_points_into("/h/moon/1.2.3/bin/moon", "/h/moon/1.2.3"))
  assert_false(shim_points_into("/h/moon/1.2.3/binx/moon", "/h/moon/1.2.3"))
  assert_false(shim_points_into("/h/moon/1.2.4/bin/moon", "/h/moon/1.2.3"))
  assert_false(shim_points_into("/usr/bin/moon", "/h/moon/1.2.3"))
}

///|
test "readlink" {
  let root = temp_path() + ".d"
  let link = path_join(root, "link")
  let plain = path_join(root, "plain")
  mkdir_p(root)
  write_text(plain, "x")
  ignore(run_ok("ln -sfn /some/target " + shell_quote(link)))
  assert_eq(readlink(link), Some("/some/target"))
  // Dangling links still resolve, plain files do not.
  assert_eq(readlink(path_join(root, "missing")), None)
  assert_eq(readlink(plain), None)
  rm_rf(root)
}

///|
test "remove_shims_in only removes links into the toolchain" {
  let root = temp_path() + ".d"
  let bin = path_join(root, "bin")
  let tc = path_join(root, "moon/1.2.3")
  let tbin = path_join(tc, "bin")
  mkdir_p(tbin)
  mkdir_p(bin)
  write_text(path_join(tbin, "moon"), "#!/bin/sh\n")
  write_text(path_join(tbin, "moonc"), "#!/bin/sh\n")
  for name in ["moon", "moonc"] {
    ignore(
      run_ok(
        "ln -sfn " +
        shell_quote(path_join(tbin, name)) +
        " " +
        shell_quote(path_join(bin, name)),
      ),
    )
  }
  // A link pointing elsewhere and a regular file must survive.
  ignore(run_ok("ln -sfn /usr/bin/env " + shell_quote(path_join(bin, "env"))))
  write_text(path_join(bin, "keep"), "x")
  remove_shims_in(bin, tc)
  assert_false(path_exists(path_join(bin, "moon")))
  assert_false(path_exists(path_join(bin, "moonc")))
  assert_true(path_exists(path_join(bin, "env")))
  assert_true(path_exists(path_join(bin, "keep")))
  rm_rf(root)
}

///|
test "ToolMeta json: legacy records without `bin` still parse" {
  let legacy : ToolMeta = @json.from_json(
    @json.parse(
      "{\"name\":\"bobzhang/zip\",\"version\":\"0.1.1\",\"bins\":[\"main\"]}",
    ),
  )
  assert_eq(legacy.name, "bobzhang/zip")
  assert_eq(legacy.version, "0.1.1")
  assert_eq(legacy.bins, ["main"])
  assert_eq(legacy.bin, None)
  let round : ToolMeta = @json.from_json(
    @json.to_json({
      name: "a/b",
      version: "2.0.0",
      bins: ["x", "y"],
      bin: Some("/opt/bin"),
    }),
  )
  assert_eq(round.bin, Some("/opt/bin"))
  assert_eq(round.bins, ["x", "y"])
}
