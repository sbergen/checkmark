import checkmark/internal/code_extractor.{type File, extract_function}
import gleam/string

pub fn extract_function_test() {
  let module =
    load_module([
      "import gleam/result",
      "",
      "pub fn main() {",
      "  Ok(42)",
      "}",
      "",
    ])

  assert extract_function(module, "main")
    == Ok(
      join([
        "pub fn main() {",
        "  Ok(42)",
        "}",
      ]),
    )
}

fn join(lines: List(String)) -> String {
  string.join(lines, "\n")
}

fn load_module(lines: List(String)) -> File {
  let assert Ok(file) = code_extractor.load(join(lines))
  file
}
