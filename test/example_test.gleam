import checkmark
import envoy

pub fn example_test() {
  assert checkmark.new()
    |> checkmark.document("README.md", fn(doc) {
      doc
      |> checkmark.should_contain_contents_of("./example.sh", tagged: "deps")
      |> checkmark.should_contain_contents_of(
        "./test/example_test.gleam",
        tagged: "markdown",
      )
      |> checkmark.should_contain_snippet_from(
        "./test/doc_snippets_test.gleam",
        checkmark.function_body("update_docs_test"),
        tagged: "update comments",
      )
    })
    // Update locally, check on CI
    |> checkmark.check_or_update(
      when: envoy.get("GITHUB_WORKFLOW") == Error(Nil),
    )
    == Ok(Nil)
}
