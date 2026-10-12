// Round-trip coverage for archive extraction.

///|
test "extract_zip writes nested files" {
  let content = @utf8.encode("hello zip")
  let f = @file.File::stored_of_bytes(content, 0, content.length())
  let entry = @member.make(@fpath.Fpath("nested/hello.txt"), @member.File(f))
  let archive = @zip.Archive::empty()
  archive.add(entry)
  let bytes = archive.to_bytes()
  let dir = @mb.run_capture("mktemp -d").trim().to_owned()
  @mb.extract_zip(bytes, dir)
  let out = @mb.read_text(
    @mb.path_join(@mb.path_join(dir, "nested"), "hello.txt"),
  )
  assert_eq(out, "hello zip")
  @mb.rm_rf(dir)
}

///|
test "extract_zip refuses path escapes" {
  let content = @utf8.encode("escape")
  let f = @file.File::stored_of_bytes(content, 0, content.length())
  let entry = @member.make(@fpath.Fpath("../evil.txt"), @member.File(f))
  let archive = @zip.Archive::empty()
  archive.add(entry)
  let dir = @mb.run_capture("mktemp -d").trim().to_owned()
  @mb.extract_zip(archive.to_bytes(), dir)
  let evil = @mb.path_join(@mb.parent_dir(dir), "evil.txt")
  assert_false(@mb.path_exists(evil))
  @mb.rm_rf(dir)
}
