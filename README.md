# checkmark

[![Package Version](https://img.shields.io/hexpm/v/checkmark)](https://hex.pm/packages/checkmark)
[![Hex Docs](https://img.shields.io/badge/hex-docs-ffaff3)](https://hexdocs.pm/checkmark/)

Checkmark is a library for either checking that code in markdown files
matches content in files, or to automatically update it.

## Example

```sh
gleam add --dev checkmark simplifile envoy
```

```gleam
import checkmark
import envoy
import simplifile

pub fn example_test() {
  assert checkmark.new(simplifile.read, simplifile.write)
    |> checkmark.file("README.md")
    |> checkmark.should_contain_contents_of("./example.sh", tagged: "sh")
    |> checkmark.should_contain_contents_of(
      "./test/example_test.gleam",
      tagged: "gleam",
    )
    // Update locally, check on CI
    |> checkmark.check_or_update(
      when: envoy.get("GITHUB_WORKFLOW") == Error(Nil),
    )
    == Ok(Nil)
}
```

These examples are, in fact, kept up to date and checked using checkmark!

Further documentation can be found at <https://hexdocs.pm/checkmark>.
