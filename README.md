# checkmark

Checkmark is a library for checking that gleam code in markdown files
type checks, builds, or runs successfully.

I have not published it as a hex package yet,
but plan on doing so soon, after getting some feedback.

## Example

```gleam
import checkmark
import filepath
import gleam/string
import simplifile

pub fn main() {
  let assert Ok(cwd) = simplifile.current_directory()
  let file = filepath.join(cwd, "README.md")

  // Checks that a single gleam code block in README.md that start with "import"
  // passes type checks, adding "my_dependency" as a package.
  let assert Ok([Ok(Nil)]) =
    checkmark.check(
      in: file,
      using: ["my_dependency"],
      selecting: string.starts_with(_, "import"),
      operation: checkmark.Check,
    )
}
```
