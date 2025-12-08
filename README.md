# checkmark

[![Package Version](https://img.shields.io/hexpm/v/checkmark)](https://hex.pm/packages/checkmark)
[![Hex Docs](https://img.shields.io/badge/hex-docs-ffaff3)](https://hexdocs.pm/checkmark/)

Checkmark helps you keep your markdown code snippets up to date!
You can either check that snippets match sources,
or automatically update them.

A source (of truth) can be one of the following:
* An entire file (any language)
* A full Gleam function definition
* A Gleam function body
* A Gleam type definition

A target to check or update can be:
* A code snippet in a markdown file
* A markdown code snippet in a Gleam comment

All types of sources and targets can be freely matched.

## Examples

Add the dependencies required by the example:

```sh deps
gleam add --dev checkmark simplifile envoy
```

Update a markdown file:

```gleam markdown
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
```

Update comments in code:

```gleam comments
let checker = checkmark.new(simplifile.read, simplifile.write)
let assert Ok(snippets) =
  checkmark.load_snippet_source(checker, "./test/doc_snippets_test.gleam")
assert checker
  |> checkmark.comments_in("./src/checkmark.gleam")
  |> checkmark.should_contain_snippet_from(
    snippets,
    checkmark.FunctionBody("contents_of_example"),
    tagged: "contents_of",
  )
  |> checkmark.should_contain_snippet_from(
    snippets,
    checkmark.FunctionBody("snippet_from_example"),
    tagged: "snippet_from",
  )
  // Update locally, check on CI
  |> checkmark.check_or_update(
    when: envoy.get("GITHUB_WORKFLOW") == Error(Nil),
  )
  == Ok(Nil)
```

These examples are, in fact, kept up to date and checked using checkmark!

Further documentation can be found at <https://hexdocs.pm/checkmark>.
