import checkmark/internal/extractor
import gleam/string
import gleeunit/should

pub fn extract_test() {
  let input =
    "This is not code
```gleam
import gleam

This is code
that should be checked
```
More text

```gleam
This is code that should not be checked
```
"

  extractor.extract_gleam_code(input, string.starts_with(_, "import"))
  |> should.equal([
    "import gleam

This is code
that should be checked
",
  ])
}
