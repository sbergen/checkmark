# checkmark

[![Package Version](https://img.shields.io/hexpm/v/checkmark)](https://hex.pm/packages/checkmark)
[![Hex Docs](https://img.shields.io/badge/hex-docs-ffaff3)](https://hexdocs.pm/checkmark/)

Checkmark is a library for checking that gleam code in markdown files
type checks, builds, or runs successfully.

## Example

```sh
gleam add checkmark
```

```gleam
import checkmark
import gleam/string

pub fn main() {
  // Checks that a single gleam code block in README.md that starts with "import"
  // passes type checks, by creating the temporary file `checkmark_tmp.gleam`
  // Checking in a temporary project is also supported.
  let assert Ok([Ok(_)]) =
    checkmark.new()
    |> checkmark.snippets_in("README.md")
    |> checkmark.filtering(string.starts_with(_, "import"))
    |> checkmark.check_in_current_package("checkmark_tmp.gleam")
}
```

Further documentation can be found at <https://hexdocs.pm/checkmark>.
