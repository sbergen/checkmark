import checkmark
import envoy
import simplifile

pub fn example_test() {
  let checker = checkmark.new(simplifile.read, simplifile.write)

  let assert Ok(snippets) =
    checkmark.load_snippet_source(checker, "./test/doc_snippets_test.gleam")

  assert checker
    |> checkmark.document("README.md")
    |> checkmark.should_contain_contents_of("./example.sh", tagged: "sh deps")
    |> checkmark.should_contain_contents_of(
      "./test/example_test.gleam",
      tagged: "gleam markdown",
    )
    |> checkmark.should_contain_snippet_from(
      snippets,
      checkmark.FunctionBody("update_docs_test"),
      tagged: "comments",
    )
    // Update locally, check on CI
    |> checkmark.check_or_update(
      when: envoy.get("GITHUB_WORKFLOW") == Error(Nil),
    )
    == Ok(Nil)
}
