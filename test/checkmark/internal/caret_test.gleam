import checkmark/internal/caret.{CrLf, Lf}

pub fn empty_doc_test() {
  let doc = caret.document_from_string("")
  assert caret.line_count(doc) == 0
  assert caret.line_ending(doc) == Lf
}

pub fn line_ending_test() {
  let doc = caret.document_from_string("\r\n")
  assert caret.line_ending(doc) == CrLf

  let doc = caret.document_from_string("\n")
  assert caret.line_ending(doc) == Lf

  // The majority wins
  let doc = caret.document_from_string("\r\n\r\n\n")
  assert caret.line_ending(doc) == CrLf

  // Ties are Lf
  let doc = caret.document_from_string("\r\n\r\n\n\n")
  assert caret.line_ending(doc) == Lf
}

pub fn single_newline_is_two_empty_lines_test() {
  let doc = caret.document_from_string("\n")
  assert caret.line_count(doc) == 2
  assert caret.get_line(doc, 0) == Ok("")
  assert caret.get_line(doc, 1) == Ok("")
}

pub fn two_newlines_is_three_empty_lines_test() {
  let doc = caret.document_from_string("\n\n")
  assert caret.line_count(doc) == 3
  assert caret.get_line(doc, 0) == Ok("")
  assert caret.get_line(doc, 1) == Ok("")
  assert caret.get_line(doc, 2) == Ok("")
}

pub fn single_line_with_newline_is_two_lines_test() {
  let doc = caret.document_from_string("Wibble\n")
  assert caret.line_count(doc) == 2
  assert caret.get_line(doc, 0) == Ok("Wibble")
  assert caret.get_line(doc, 1) == Ok("")
}

pub fn leading_newline_test() {
  let doc = caret.document_from_string("\nWibble\n")
  assert caret.line_count(doc) == 3

  assert caret.get_line(doc, 0) == Ok("")
  assert caret.get_line(doc, 1) == Ok("Wibble")
  assert caret.get_line(doc, 2) == Ok("")
}

pub fn get_line_test() {
  let content =
    "First
Second

Third"

  let doc = caret.document_from_string(content)

  assert caret.get_line(doc, -1) == Error(Nil)
  assert caret.get_line(doc, 0) == Ok("First")
  assert caret.get_line(doc, 1) == Ok("Second")
  assert caret.get_line(doc, 2) == Ok("")
  assert caret.get_line(doc, 3) == Ok("Third")
  assert caret.get_line(doc, 4) == Error(Nil)
}
