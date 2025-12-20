import checkmark
import envoy
import simplifile
// pub fn update_docs_test() {
//   let checker = checkmark.new(simplifile.read, simplifile.write)
// 
//   let assert Ok(snippets) =
//     checkmark.load_snippet_source(checker, "./test/doc_snippets_test.gleam")
// 
//   assert checker
//     |> checkmark.comments_in("./src/checkmark.gleam")
//     |> checkmark.should_contain_snippet_from(
//       snippets,
//       checkmark.function_body("contents_of_example"),
//       tagged: "contents_of",
//     )
//     |> checkmark.should_contain_snippet_from(
//       snippets,
//       checkmark.function_body("snippet_from_example"),
//       tagged: "snippet_from",
//     )
//     // Update locally, check on CI
//     |> checkmark.check_or_update(
//       when: envoy.get("GITHUB_WORKFLOW") == Error(Nil),
//     )
//     == Ok(Nil)
// }
// 
// pub fn contents_of_example(checker: checkmark.Checker(a)) -> checkmark.File(a) {
//   checker
//   |> checkmark.document("README.md")
//   |> checkmark.should_contain_contents_of("./example.sh", tagged: "sh deps")
// }
// 
// pub fn snippet_from_example(
//   checker: checkmark.Checker(a),
//   snippets: checkmark.CodeSnippetSource,
// ) -> checkmark.File(a) {
//   checker
//   |> checkmark.document("README.md")
//   |> checkmark.should_contain_snippet_from(
//     snippets,
//     checkmark.function("wibble"),
//     tagged: "wibble",
//   )
// }
