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

pub fn to_string_with_trailing_newline_test() {
  let content = "1\n2\n3\n4\n"
  assert caret.from_string(content) |> caret.to_string == content
}

pub fn to_string_without_trailing_newline_test() {
  let content = "123"
  assert caret.from_string(content) |> caret.to_string == content
}

pub fn slice_lines_basic_test() {
  let assert Ok(slice) =
    caret.from_string("1\n2\n3\n4")
    |> caret.slice_lines(1, 2)

  caret.to_string(slice) == "2\n3"
}

pub fn slice_lines_negative_test() {
  let assert Ok(slice) =
    caret.from_string("1\n2\n3\n4")
    |> caret.slice_lines(1, -1)

  caret.to_string(slice) == "1\n2"
}

pub fn slice_lines_zero_test() {
  let assert Ok(slice) =
    caret.from_string("1\n2\n3\n4")
    |> caret.slice_lines(1, 0)

  caret.to_string(slice) == ""
}

pub fn slice_lines_error_test() {
  let text = caret.from_string("1\n2\n3\n4")
  assert caret.slice_lines(text, 0, 10) == Error(Nil)
  assert caret.slice_lines(text, 10, 1) == Error(Nil)
}

pub fn replace_lines_test() {
  let text = caret.from_string("1\n2\n3\n4")
  let replacement = caret.from_string("Two\nThree")

  let assert Ok(replaced) =
    caret.replace_lines(text, at: 1, replace: 2, with: replacement)

  assert caret.to_string(replaced) == "1\nTwo\nThree\n4"
}

pub fn auto_unindent_test() {
  let text =
    "
   1
    2
  3"

  assert caret.from_string(text)
    |> caret.auto_unindent
    |> caret.to_string
    == "\n 1\n  2\n3"
}

pub fn auto_unindent_two_levels_test() {
  let text =
    "
    1
      2
       3"

  assert caret.from_string(text)
    |> caret.auto_unindent
    |> caret.to_string
    == "\n1\n  2\n   3"
}

pub fn auto_unindent_tabs_test() {
  // This should be only one tab stop
  let text =
    "\t\t1
 \t 2"

  assert caret.from_string(text)
    |> caret.auto_unindent
    |> caret.to_string
    == "\t1\n 2"
}

pub fn unindent_test() {
  let text =
    "1
 2
\t3
   4
   \t5"

  assert caret.from_string(text)
    |> caret.unindent(1)
    |> caret.to_string
    == "1\n2\n3\n 4\n \t5"
}

pub fn unindent_two_level_test() {
  let text =
    "1
    2
      3"

  assert caret.from_string(text)
    |> caret.unindent(2)
    |> caret.to_string
    == "1\n2\n  3"
}
