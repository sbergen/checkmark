import checkmark.{
  type Configuration, CouldNotParseSnippetSource, MultipleTagsFound, TagNotFound,
}

import gleam/erlang/process
import gleeunit
import simplifile

pub fn main() {
  gleeunit.main()
}

pub fn check_existing_file_test() {
  let assert Error(errors) =
    checkmark.new()
    |> checkmark.document("test_assets/test.md", fn(doc) {
      doc
      |> checkmark.should_contain_contents_of(
        "./test_assets/test_content.txt",
        tagged: "multiple",
      )
      |> checkmark.should_contain_contents_of(
        "./test_assets/test_content.txt",
        tagged: "single",
      )
      |> checkmark.should_contain_contents_of(
        "./test_assets/test_content.txt",
        tagged: "not_present",
      )
    })
    |> checkmark.check()

  assert errors.file_errors == []
  assert errors.content_errors
    == [
      MultipleTagsFound("test_assets/test.md", "multiple", [1, 6]),
      TagNotFound("test_assets/test.md", "not_present"),
    ]
}

pub fn check_missing_markdown_file_test() {
  let assert Error(errors) =
    checkmark.new()
    |> checkmark.document("this-file-does-not-exist", fn(doc) { doc })
    |> checkmark.check()

  assert errors.file_errors
    == [#("this-file-does-not-exist", simplifile.Enoent)]
}

pub fn check_missing_source_file_test() {
  let assert Error(errors) =
    checkmark.new()
    |> checkmark.document("./test_assets/test.md", fn(doc) {
      doc
      |> checkmark.should_contain_contents_of("this-file-does-not-exist", "")
    })
    |> checkmark.check()

  assert errors.file_errors
    == [#("this-file-does-not-exist", simplifile.Enoent)]
}

pub fn invalid_snippet_source_test() {
  let assert Error(errors) =
    checkmark.new()
    |> checkmark.document("./test_assets/test.md", fn(doc) {
      doc
      |> checkmark.should_contain_snippet_from(
        "./test_assets/test.md",
        checkmark.function("Wibble"),
        tagged: "wibble",
      )
    })
    |> checkmark.check()

  assert errors.content_errors
    == [CouldNotParseSnippetSource("./test_assets/test.md")]
}

pub fn update_markdown_test() {
  use config <- update_test("./test_assets/expected_updated.md")

  config
  |> checkmark.document(
    "./test_assets/update.md",
    checkmark.should_contain_contents_of(
      _,
      "./test_assets/test_content.txt",
      "update",
    ),
  )
}

pub fn update_code_test() {
  use config <- update_test("./test_assets/expected_updated.gleam")

  config
  |> checkmark.comments_in("./test_assets/test.gleam", fn(file) {
    file
    |> checkmark.should_contain_contents_of(
      "./test_assets/test_content.txt",
      "module",
    )
    |> checkmark.should_contain_contents_of(
      "./test_assets/test_content.txt",
      "value",
    )
  })
}

pub fn update_from_snippets_test() {
  let snippets = "./test_assets/snippet_source.gleam"
  use config <- update_test("./test_assets/expected_snippets.md")

  config
  |> checkmark.document("./test_assets/snippets.md", fn(doc) {
    doc
    |> checkmark.should_contain_snippet_from(
      snippets,
      checkmark.function("main"),
      "function",
    )
    |> checkmark.should_contain_snippet_from(
      snippets,
      checkmark.function_body("main"),
      "function body",
    )
    |> checkmark.should_contain_snippet_from(
      snippets,
      checkmark.type_definition("Wibble"),
      "type",
    )
    |> checkmark.should_contain_snippet_from(
      snippets,
      checkmark.type_alias("Wobble"),
      "type alias",
    )
  })
}

fn update_test(
  expected: String,
  configure: fn(Configuration) -> Configuration,
) -> Nil {
  let self = process.new_subject()
  let write = fn(_, content) {
    process.send(self, content)
    Ok(Nil)
  }

  assert checkmark.new()
    |> configure
    |> checkmark.update_with_writer(write)
    == Ok(Nil)

  let assert Ok(written) = process.receive(self, 0)
  let assert Ok(expected) = simplifile.read(expected)
  assert written == expected
}
