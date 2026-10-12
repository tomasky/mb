///|
/// JSON accessors used when talking to the MoonBit and mooncakes.io APIs.

///|
pub fn json_field(obj : Json, key : String) -> Json? {
  match obj {
    Object(m) => m.get(key)
    _ => None
  }
}

///|
pub fn json_string(obj : Json, key : String) -> String? {
  match json_field(obj, key) {
    Some(String(s)) => Some(s)
    _ => None
  }
}

///|
pub fn json_bool(obj : Json, key : String) -> Bool? {
  match json_field(obj, key) {
    Some(True) => Some(true)
    Some(False) => Some(false)
    _ => None
  }
}

///|
pub fn json_array(obj : Json, key : String) -> Array[Json]? {
  match json_field(obj, key) {
    Some(Array(a)) => Some(a)
    _ => None
  }
}

///|
pub fn json_object(obj : Json, key : String) -> Json? {
  match json_field(obj, key) {
    Some(Object(_) as o) => Some(o)
    _ => None
  }
}
