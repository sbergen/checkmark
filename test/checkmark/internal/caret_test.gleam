import checkmark/internal/caret.{CrLf, Lf, ReplaceLines}
import gleam/int
import gleam/list
import gleam/result

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

pub fn with_tab_stop_test() {
  // The first line would count as three indents at 2,
  // but counts as only one indent with 4.
  let text =
    "
      1
       2"

  assert caret.from_string(text)
    |> caret.with_tab_stop_width(4)
    |> caret.auto_unindent()
    |> caret.to_string
    == "\n  1\n   2"
}

pub fn fold_test() {
  assert caret.from_string("1\n2\nfoo\n3")
    |> caret.fold_lines(0, fn(sum, line) {
      sum + result.unwrap(int.parse(line), 0)
    })
    == 6
}

pub fn fold_right_test() {
  assert caret.from_string("1\n2\n3")
    |> caret.fold_lines_right([], list.prepend)
    == ["1", "2", "3"]
}

pub fn apply_all_lines_test() {
  let text = caret.from_string("1\n2\n3\n4\n5")
  let replacement1 = caret.from_string("Two & Three")
  let replacement2 = caret.from_string("f\no\nu\nr")
  let replacement3 = caret.from_string("five\n")
  let edits = [
    ReplaceLines(at: 1, count: 2, with: replacement1),
    ReplaceLines(at: 3, count: 1, with: replacement2),
    ReplaceLines(at: 4, count: 1, with: replacement3),
  ]

  let assert Ok(edited) = caret.apply_all(text, edits)
  assert caret.to_string(edited) == "1
Two & Three
f
o
u
r
five
"
}

pub fn apply_all_insert_test() {
  let assert Ok(text) =
    caret.from_string("1\n2\n3")
    |> caret.apply_all([
      ReplaceLines(at: 1, count: 0, with: caret.from_string("and")),
      ReplaceLines(at: 2, count: 0, with: caret.from_string("and")),
    ])
  assert caret.to_string(text) == "1
and
2
and
3"
}

pub fn apply_all_error_test() {
  assert caret.from_string("")
    |> caret.apply_all([
      ReplaceLines(at: 1, count: 10, with: caret.from_string("wibble")),
    ])
    == Error(Nil)
}

pub fn map_lines_test() {
  assert caret.from_string("1\n2\n3")
    |> caret.map_lines(fn(l) { l <> l })
    |> caret.to_string
    == "11\n22\n33"
}

pub fn without_trailing_newline_test() {
  assert caret.from_string("")
    |> caret.without_trailing_newline
    |> caret.to_string
    == ""

  assert caret.from_string("wibble\n")
    |> caret.without_trailing_newline
    |> caret.to_string
    == "wibble"

  assert caret.from_string("wibble")
    |> caret.without_trailing_newline
    |> caret.to_string
    == "wibble"

  assert caret.from_string("wibble\n\n")
    |> caret.without_trailing_newline
    |> caret.to_string
    == "wibble\n"
}

pub fn tranform_line_range_test() {
  let assert Ok(text) =
    caret.from_string("  1\n  2\n  3\n  4")
    |> caret.transform_line_range(at: 1, count: 2, with: caret.auto_unindent)

  assert caret.to_string(text) == "  1\n2\n3\n  4"
}
