import checkmark
import envoy

pub fn update_docs_test() {
  let snippet_source = "./test/doc_snippets_test.gleam"

  assert checkmark.new()
    |> checkmark.comments_in("./src/checkmark.gleam", fn(doc) {
      doc
      |> checkmark.should_contain_snippet_from(
        snippet_source,
        checkmark.function_body("contents_of_example"),
        tagged: "contents_of",
      )
      |> checkmark.should_contain_snippet_from(
        snippet_source,
        checkmark.function_body("snippet_from_example"),
        tagged: "snippet_from",
      )
    })
    // Update locally, check on CI
    |> checkmark.check_or_update(
      when: envoy.get("GITHUB_WORKFLOW") == Error(Nil),
    )
    == Ok(Nil)
}

pub fn contents_of_example() -> checkmark.Configuration {
  checkmark.new()
  |> checkmark.document("README.md", fn(doc) {
    doc
    |> checkmark.should_contain_contents_of("./example.sh", tagged: "deps")
  })
}

pub fn snippet_from_example() -> checkmark.Configuration {
  checkmark.new()
  |> checkmark.document("README.md", fn(doc) {
    doc
    |> checkmark.should_contain_snippet_from(
      "my_file.gleam",
      checkmark.function("wibble"),
      tagged: "wibble",
    )
  })
}
