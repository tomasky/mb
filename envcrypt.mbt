///|
/// Authenticated encryption for env values.
///
/// `moonbitlang/x/crypto` provides ChaCha20 but no AEAD (no ChaCha20-Poly1305
/// or AES-GCM), so values are encrypted with ChaCha20 and authenticated with
/// HMAC-SHA256 in the encrypt-then-MAC order: the tag is checked before
/// anything is decrypted. The key is a user-supplied string from which two
/// independent subkeys are derived with HMAC-SHA256.
///
/// An encrypted value is written as `ENC[<hex>]` where the hex blob is
/// `nonce (12) || tag (32) || ciphertext`.

///|
fn hex_value(c : Char) -> Int? {
  if c >= '0' && c <= '9' {
    Some(c.to_int() - '0'.to_int())
  } else if c >= 'a' && c <= 'f' {
    Some(c.to_int() - 'a'.to_int() + 10)
  } else if c >= 'A' && c <= 'F' {
    Some(c.to_int() - 'A'.to_int() + 10)
  } else {
    None
  }
}

///|
fn hex_to_bytes(hex : String) -> Bytes? {
  let chars = hex.trim().to_array()
  if chars.length() % 2 != 0 {
    return None
  }
  let out : Array[Byte] = []
  let mut i = 0
  while i < chars.length() {
    match (hex_value(chars[i]), hex_value(chars[i + 1])) {
      (Some(hi), Some(lo)) => out.push(((hi << 4) | lo).to_byte())
      _ => return None
    }
    i = i + 2
  }
  Some(Bytes::from_array(out))
}

///|
fn bytes_slice(b : Bytes, start : Int, end : Int) -> Bytes {
  let out : Array[Byte] = []
  let mut i = start
  while i < end {
    out.push(b[i])
    i = i + 1
  }
  Bytes::from_array(out)
}

///|
fn hmac_sha256(key : Bytes, msg : Bytes) -> Bytes {
  @crypto.hmac(@crypto.SHA256::new(), key, msg).unsafe_reinterpret_as_bytes()
}

///|
fn chacha20_xor(
  key : Bytes,
  nonce : Bytes,
  data : Bytes,
) -> Bytes raise MbError {
  let cipher = @crypto.ChaCha::chacha20(key, nonce) catch {
    _ => raise MbError("failed to initialise ChaCha20")
  }
  let out = FixedArray::make(data.length(), b'\x00')
  cipher.transform(data, out)
  out.unsafe_reinterpret_as_bytes()
}

///|
fn constant_time_eq(a : Bytes, b : Bytes) -> Bool {
  if a.length() != b.length() {
    return false
  }
  let mut diff = 0
  let mut i = 0
  while i < a.length() {
    diff = diff | ((a[i].to_int() & 0xff) ^ (b[i].to_int() & 0xff))
    i = i + 1
  }
  diff == 0
}

///|
/// True when a dotenv value is an `ENC[...]` blob rather than plain text.
pub fn is_encrypted_value(value : String) -> Bool {
  value.has_prefix("ENC[") && value.has_suffix("]")
}

///|
/// Derive a 32-byte subkey for `purpose` from the user's master key.
fn subkey(master : String, purpose : String) -> Bytes {
  hmac_sha256(@utf8.encode(master), @utf8.encode(purpose))
}

///|
/// Encrypt `plain` into an `ENC[...]` value using `master`.
pub fn encrypt_value(plain : String, master : String) -> String raise MbError {
  let enc_key = subkey(master, "mb-env/enc")
  let mac_key = subkey(master, "mb-env/mac")
  let nonce = match @env.rand(12) {
    Some(b) => b
    None => raise MbError("failed to generate a random nonce")
  }
  let ciphertext = chacha20_xor(enc_key, nonce, @utf8.encode(plain))
  let tag = hmac_sha256(mac_key, nonce + ciphertext)
  "ENC[" + @crypto.bytes_to_hex_string(nonce + tag + ciphertext) + "]"
}

///|
/// Decrypt an `ENC[...]` value using `master`.
pub fn decrypt_value(value : String, master : String) -> String raise MbError {
  if !is_encrypted_value(value) {
    return value
  }
  let body = value[4:value.length() - 1].to_owned()
  let blob = match hex_to_bytes(body) {
    Some(b) => b
    None => raise MbError("malformed encrypted value")
  }
  if blob.length() < 44 {
    raise MbError("malformed encrypted value")
  }
  let nonce = bytes_slice(blob, 0, 12)
  let tag = bytes_slice(blob, 12, 44)
  let ciphertext = bytes_slice(blob, 44, blob.length())
  let mac_key = subkey(master, "mb-env/mac")
  if !constant_time_eq(hmac_sha256(mac_key, nonce + ciphertext), tag) {
    raise MbError("could not decrypt: wrong key or corrupted value")
  }
  let enc_key = subkey(master, "mb-env/enc")
  @utf8.decode_lossy(chacha20_xor(enc_key, nonce, ciphertext))
}
