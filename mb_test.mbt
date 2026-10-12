// Blackbox tests exercising the public `kupas/mb` API through `@mb`.

///|
test "public path helpers" {
  assert_eq(@mb.path_join("a", "b"), "a/b")
  assert_eq(@mb.path_join_all(["a", "b", "c"]), "a/b/c")
  assert_eq(@mb.parent_dir("/a/b"), "/a")
  assert_eq(@mb.base_name("/a/b"), "b")
}

///|
test "public shell_quote" {
  assert_eq(@mb.shell_quote("plain"), "'plain'")
  assert_eq(@mb.shell_quote("a'b"), "'a'\\''b'")
}

///|
test "public sha256_hex" {
  assert_eq(
    @mb.sha256_hex(@utf8.encode("hello")),
    "2cf24dba5fb0a30e26e83b2ac5b9e29e1b161e5c1fa7425e73043362938b9824",
  )
}

///|
test "public json accessors" {
  let j = @json.parse("{\"name\":\"moonbitlang/x\",\"version\":\"0.5.5\"}")
  assert_eq(@mb.json_string(j, "name"), Some("moonbitlang/x"))
  assert_eq(@mb.json_string(j, "version"), Some("0.5.5"))
  assert_eq(@mb.json_string(j, "missing"), None)
}

///|
test "public shim_points_into" {
  assert_true(@mb.shim_points_into("/h/moon/1/bin/moon", "/h/moon/1"))
  assert_false(@mb.shim_points_into("/h/moon/1/bin/moon", "/h/moon/2"))
}
