import checkmark
import filepath
import gleam/string
import gleeunit
import gleeunit/should
import simplifile

pub fn main() {
  gleeunit.main()
}

pub fn check_test() {
  let assert Ok(cwd) = simplifile.current_directory()
  let file =
    filepath.join(cwd, "test")
    |> filepath.join("sample.md")

  let assert Ok([Ok(Nil)]) =
    checkmark.check(
      in: file,
      using: ["filepath"],
      selecting: string.starts_with(_, "import"),
      operation: checkmark.Check,
    )
}

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

  checkmark.extract_gleam_code(input, string.starts_with(_, "import"))
  |> should.equal([
    "import gleam

This is code
that should be checked
",
  ])
}
