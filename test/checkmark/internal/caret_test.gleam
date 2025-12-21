import checkmark/internal/caret.{CrLf, Lf}

pub fn empty_text_test() {
  let text = caret.from_string("")
  assert caret.line_count(text) == 0
  assert caret.line_ending(text) == Lf
}

pub fn line_ending_test() {
  let text = caret.from_string("\r\n")
  assert caret.line_ending(text) == CrLf

  let text = caret.from_string("\n")
  assert caret.line_ending(text) == Lf

  // The majority wins
  let text = caret.from_string("\r\n\r\n\n")
  assert caret.line_ending(text) == CrLf

  // Ties are Lf
  let text = caret.from_string("\r\n\r\n\n\n")
  assert caret.line_ending(text) == Lf
}

pub fn single_newline_is_two_empty_lines_test() {
  let text = caret.from_string("\n")
  assert caret.line_count(text) == 2
  assert caret.line(text, 0) == Ok("")
  assert caret.line(text, 1) == Ok("")
}

pub fn two_newlines_is_three_empty_lines_test() {
  let text = caret.from_string("\n\n")
  assert caret.line_count(text) == 3
  assert caret.line(text, 0) == Ok("")
  assert caret.line(text, 1) == Ok("")
  assert caret.line(text, 2) == Ok("")
}

pub fn single_line_with_newline_is_two_lines_test() {
  let text = caret.from_string("Wibble\n")
  assert caret.line_count(text) == 2
  assert caret.line(text, 0) == Ok("Wibble")
  assert caret.line(text, 1) == Ok("")
}

pub fn leading_newline_test() {
  let text = caret.from_string("\nWibble\n")
  assert caret.line_count(text) == 3

  assert caret.line(text, 0) == Ok("")
  assert caret.line(text, 1) == Ok("Wibble")
  assert caret.line(text, 2) == Ok("")
}

pub fn line_test() {
  let content =
    "First

Second"

  let text = caret.from_string(content)

  assert caret.line(text, -1) == Error(Nil)
  assert caret.line(text, 0) == Ok("First")
  assert caret.line(text, 1) == Ok("")
  assert caret.line(text, 2) == Ok("Second")
  assert caret.line(text, 3) == Error(Nil)
}
