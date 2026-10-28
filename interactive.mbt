///|
/// Interactive terminal helpers for `mb tool install -i`.
///
/// The prompt reads single keypresses from a raw terminal and renders a
/// checkbox list with ANSI escapes. ESC cancels.

///|
/// Whether a prompt can be shown (stdin and stdout are terminals).
fn can_prompt() -> Bool {
  mb_isatty_stdin() != 0 && is_tty()
}

///|
/// Write raw text to stdout without a trailing newline.
fn write_raw(text : String) -> Unit {
  ignore(mb_write(cstring(text)))
}

///|
fn in_array(items : Array[String], s : String) -> Bool {
  for item in items {
    if item == s {
      return true
    }
  }
  false
}

///|
fn count_selected(selected : Array[Bool]) -> Int32 {
  let mut n = 0
  for s in selected {
    if s {
      n = n + 1
    }
  }
  n
}

///|
fn render_select(
  names : Array[String],
  selected : Array[Bool],
  cursor : Int32,
  redraw : Bool,
) -> Unit {
  let mut out = ""
  if redraw {
    out = out + "\u{1B}[" + (names.length() + 1).to_string() + "A"
  }
  out = out + "\r\u{1B}[J"
  out = out +
    "Select executables to install  (\u{2191}/\u{2193} move, space toggle, a all, enter confirm, esc cancel)\n"
  for i, name in names {
    let arrow = if i == cursor { "\u{276F}" } else { " " }
    let mark = if selected[i] { "x" } else { " " }
    out = out + "  " + arrow + " [" + mark + "] " + name + "\n"
  }
  write_raw(out)
}

///|
fn clear_select(lines : Int32) -> Unit {
  write_raw("\u{1B}[" + (lines + 1).to_string() + "A\r\u{1B}[J")
}

///|
/// Ask the user which executables to install. Returns the selected names, or
/// `None` when the user cancels with ESC (or EOF).
fn select_executables(names : Array[String]) -> Array[String]? {
  let n = names.length()
  if n == 0 {
    return Some([])
  }
  let selected : Array[Bool] = Array::make(n, true)
  let mut cursor = 0
  if mb_tty_raw() != 0 {
    return None
  }
  write_raw("\u{1B}[?25l")
  render_select(names, selected, cursor, false)
  let mut result : Array[String]? = None
  while true {
    let key = mb_read_byte(0)
    if key == -1 {
      result = None
      break
    } else if key == 27 {
      // ESC: either a lone cancel or the start of an arrow-key sequence.
      let next = mb_read_byte(50)
      if next == 91 {
        let code = mb_read_byte(50)
        if code == 65 {
          cursor = (cursor + n - 1) % n
        } else if code == 66 {
          cursor = (cursor + 1) % n
        }
      } else {
        result = None
        break
      }
    } else if key == 32 {
      selected[cursor] = !selected[cursor]
    } else if key == 13 || key == 10 {
      if count_selected(selected) > 0 {
        let picked : Array[String] = []
        for i, name in names {
          if selected[i] {
            picked.push(name)
          }
        }
        result = Some(picked)
        break
      }
    } else if key == 97 || key == 65 {
      // 'a' / 'A': toggle everything.
      let all = count_selected(selected) != n
      for i = 0; i < n; i = i + 1 {
        selected[i] = all
      }
    } else if key == 106 {
      cursor = (cursor + 1) % n
    } else if key == 107 {
      cursor = (cursor + n - 1) % n
    }
    render_select(names, selected, cursor, true)
  }
  clear_select(n)
  write_raw("\u{1B}[?25h")
  ignore(mb_tty_restore())
  result
}

///|
/// Return the names to install: with `interactive` and more than one candidate,
/// ask the user; ESC cancels the install.
fn choose_names(
  names : Array[String],
  interactive : Bool,
) -> Array[String] raise MbError {
  if !interactive || names.length() <= 1 {
    return names
  }
  if !can_prompt() {
    raise MbError(
      "cannot choose executables on a non-interactive terminal; candidates: " +
      names.join(", "),
    )
  }
  match select_executables(names) {
    None => {
      println("Installation cancelled.")
      raise Coded("installation cancelled", 0)
    }
    Some(chosen) => chosen
  }
}
