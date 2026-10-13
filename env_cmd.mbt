///|
/// The `mb env` command group: manage dotenv files for the current project and
/// for the user as a whole.
///
/// - project scope (default): `./.env` (and `./.mbenv` when present);
/// - global scope (`--global`): `$HOME/.mbenv`, which also holds the key.
///
/// Values are encrypted individually, so listing a file never needs the key.

///|
/// Resolve the encryption key, prompting for one the first time it is needed.
fn env_require_key() -> String raise MbError {
  match read_env_key() {
    Some(k) => k
    None => {
      let path = global_env_file()
      println("No encryption key found.")
      println("Enter a key to encrypt env values (stored in " + path + "):")
      let key = @utf8.decode_lossy(mb_read_line()).trim().to_owned()
      if key == "" {
        raise MbError("no key provided")
      }
      let (_, entries) = read_global_env()
      write_global_env(Some(key), entries)
      println("Stored key in " + path)
      key
    }
  }
}

///|
fn env_upsert(
  entries : Array[(String, String)],
  key : String,
  value : String,
) -> Array[(String, String)] {
  let out : Array[(String, String)] = []
  let mut replaced = false
  for entry in entries {
    let (k, v) = entry
    if k == key {
      out.push((k, value))
      replaced = true
    } else {
      out.push((k, v))
    }
  }
  if !replaced {
    out.push((key, value))
  }
  out
}

///|
/// The `mb env set` command. Encrypts the value unless `plain` is set.
fn env_set(
  key : String,
  value : String,
  global : Bool,
  plain : Bool,
) -> Unit raise MbError {
  let stored = if plain {
    value
  } else {
    encrypt_value(value, env_require_key())
  }
  if global {
    let (k, entries) = read_global_env()
    write_global_env(k, env_upsert(entries, key, stored))
    println(key + " set in " + global_env_file())
  } else {
    write_env_file(".env", env_upsert(read_env_file(".env"), key, stored))
    println(key + " set in .env")
  }
}

///|
/// The `mb env rm` command: remove one or more keys.
fn env_rm(keys : Array[String], global : Bool) -> Unit raise MbError {
  let path = if global { global_env_file() } else { ".env" }
  let (existing_key, entries) = if global {
    read_global_env()
  } else {
    (None, read_env_file(path))
  }
  let out : Array[(String, String)] = []
  let mut removed = 0
  for entry in entries {
    let (k, v) = entry
    let mut drop = false
    for want in keys {
      if want == k {
        drop = true
      }
    }
    if drop {
      removed = removed + 1
    } else {
      out.push((k, v))
    }
  }
  if removed == 0 {
    raise MbError("no such key in " + path + ": " + keys.join(", "))
  }
  if global {
    write_global_env(existing_key, out)
  } else {
    write_env_file(path, out)
  }
  println("Removed " + removed.to_string() + " key(s) from " + path)
}

///|
/// The `mb env list` command.
///
/// Values are only revealed when stdout is a terminal, so a captured or piped
/// listing shows encrypted values as `<encrypted>` instead of their contents.
/// `mask` forces masking even on a terminal.
fn env_list(global : Bool, mask : Bool) -> Unit raise MbError {
  let path = if global { global_env_file() } else { ".env" }
  let reveal = !mask && is_tty()
  let entries = if reveal {
    load_env_file(path)
  } else if global {
    let (_, e) = read_global_env()
    e
  } else {
    read_env_file(path)
  }
  if entries.is_empty() {
    println("No env entries in " + path + ".")
    return
  }
  println("Env entries in " + path + ":")
  for entry in entries {
    let (k, v) = entry
    if is_encrypted_value(v) {
      println("  " + k + "=<encrypted>")
    } else {
      println("  " + k + "=" + v)
    }
  }
}
