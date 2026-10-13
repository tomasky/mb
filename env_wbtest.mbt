// Whitebox tests for dotenv parsing, encryption and the `mb env` parsers.

///|
test "parse_dotenv_line" {
  assert_eq(parse_dotenv_line("FOO=bar"), Some(("FOO", "bar")))
  assert_eq(parse_dotenv_line("export FOO=bar"), Some(("FOO", "bar")))
  assert_eq(parse_dotenv_line("  FOO = bar baz "), Some(("FOO", "bar baz")))
  assert_eq(parse_dotenv_line("FOO=\"a b\""), Some(("FOO", "a b")))
  assert_eq(parse_dotenv_line("FOO='a b'"), Some(("FOO", "a b")))
  assert_eq(parse_dotenv_line("FOO=bar # comment"), Some(("FOO", "bar")))
  assert_eq(parse_dotenv_line("FOO=\"a\\nb\""), Some(("FOO", "a\nb")))
  assert_eq(parse_dotenv_line("# comment"), None)
  assert_eq(parse_dotenv_line(""), None)
  assert_eq(parse_dotenv_line("NOEQUALS"), None)
}

///|
test "parse_dotenv" {
  let entries = parse_dotenv("A=1\nB=two\n\n# c\nC=\"x y\"\n")
  assert_eq(entries, [("A", "1"), ("B", "two"), ("C", "x y")])
}

///|
test "dotenv formatting round-trips" {
  let cases = [
    ("A", "1"),
    ("B", "hello world"),
    ("C", ""),
    ("D", "a#b"),
    ("E", "q\"q"),
    ("F", "back\\slash"),
  ]
  for case in cases {
    let (k, v) = case
    assert_eq(parse_dotenv_line(format_dotenv_line(k, v)), Some((k, v)))
  }
}

///|
test "encrypt/decrypt round-trip" {
  let secret = "s3cr3t with spaces & 汉字"
  let enc = encrypt_value(secret, "my-key")
  assert_true(is_encrypted_value(enc))
  assert_eq(decrypt_value(enc, "my-key"), secret)
  // A wrong key must be rejected by the MAC.
  let bad = decrypt_value(enc, "other-key") catch { _ => "<failed>" }
  assert_eq(bad, "<failed>")
  // A fresh random nonce makes each encryption unique.
  assert_true(encrypt_value(secret, "my-key") != enc)
}

///|
test "encrypted values can be stored and reloaded" {
  let path = temp_path() + ".env"
  let enc = encrypt_value("tok", "k")
  write_env_file(path, [("TOKEN", enc), ("PLAIN", "ok")])
  assert_eq(read_env_file(path), [("TOKEN", enc), ("PLAIN", "ok")])
  @env.set_env_var("MB_ENV_KEY", "k")
  assert_eq(load_dotenv(path), [("TOKEN", "tok"), ("PLAIN", "ok")])
  @env.unset_env_var("MB_ENV_KEY")
  rm_rf(path)
}

///|
test "hex_to_bytes" {
  assert_eq(
    hex_to_bytes("00ff10").map(b => @crypto.bytes_to_hex_string(b)),
    Some("00ff10"),
  )
  assert_eq(hex_to_bytes("0"), None)
  assert_eq(hex_to_bytes("zz"), None)
}

///|
test "parse_env_set_flags" {
  let o = parse_env_set_flags(["FOO=bar", "--global", "--plain"]).unwrap()
  assert_eq(o.key, "FOO")
  assert_eq(o.value, "bar")
  assert_true(o.global)
  assert_true(o.plain)
  // `KEY VALUE` form, and values containing `=`.
  let o2 = parse_env_set_flags(["FOO", "bar baz"]).unwrap()
  assert_eq(o2.value, "bar baz")
  let o3 = parse_env_set_flags(["URL=a=b"]).unwrap()
  assert_eq(o3.value, "a=b")
  assert_true(parse_env_set_flags([]) is Err(_))
  assert_true(parse_env_set_flags(["NOEQUALS"]) is Err(_))
  assert_true(parse_env_set_flags(["=x"]) is Err(_))
  assert_true(parse_env_set_flags(["a=b", "--bogus"]) is Err(_))
}

///|
test "parse_env_names_flags" {
  let (keys, global) = parse_env_names_flags(["A", "B", "-g"]).unwrap()
  assert_eq(keys, ["A", "B"])
  assert_true(global)
  assert_true(parse_env_names_flags([]) is Err(_))
  assert_true(parse_env_names_flags(["A", "--bogus"]) is Err(_))
}

///|
test "parse_env_list_flags" {
  assert_true(parse_env_list_flags(["-g"]).unwrap())
  assert_false(parse_env_list_flags([]).unwrap())
  assert_true(parse_env_list_flags(["x"]) is Err(_))
}
