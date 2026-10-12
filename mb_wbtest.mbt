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
    "{\"items\":[{\"name\":\"moon\",\"version\":\"0.1.20260920 (914d7da 2026-09-20)\"},{\"name\":\"moonc\",\"version\":\"v0.10.14+7d59c7ec9 (2026-09-18)\"}]}",
  )
  let items = parse_version_items(j)
  assert_eq(items.length(), 2)
  assert_eq(items[0], ("moon", "0.1.20260920"))
  assert_eq(items[1], ("moonc", "v0.10.14+7d59c7ec9"))
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
  let (v, f) = parse_version_flags(["0.10.14", "--force"], "latest")
  assert_eq(v, "0.10.14")
  assert_true(f)
  let (v2, f2) = parse_version_flags([], "latest")
  assert_eq(v2, "latest")
  assert_false(f2)
}

///|
test "parse_tool_flags" {
  let o = parse_tool_flags(
    ["bobzhang/zip@0.1.1", "--bin", "/tmp/b", "--moon=latest", "--force"],
    true,
  )
  assert_eq(o.spec, "bobzhang/zip@0.1.1")
  assert_eq(o.bin, "/tmp/b")
  assert_eq(o.moon, "latest")
  assert_true(o.force)
}
