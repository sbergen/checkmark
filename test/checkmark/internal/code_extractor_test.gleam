import checkmark/internal/caret
import checkmark/internal/code_extractor.{
  type CodeSegment, type ExtractError, Function, FunctionBody, TypeAlias,
  TypeDefinition,
}
import gleam/result

pub fn extract_function_test() {
  assert extract(
      Function("main"),
      "import gleam/result

pub fn main() {

  Ok(42)
}
",
    )
    == Ok(
      "pub fn main() {

  Ok(42)
}",
    )
}

pub fn extract_function_body_test() {
  assert extract(
      FunctionBody("main"),
      "import gleam/result

pub fn main() {
  let result = 42
  result
}",
    )
    == Ok("let result = 42\nresult")
}

pub fn extract_function_body_weird_indent_test() {
  assert extract(
      FunctionBody("main"),
      "import gleam/result

pub fn main() {
  case True {
    True -> False
// weird indent

    False -> True
  }
}
",
    )
    == Ok(
      "  case True {
    True -> False
// weird indent

    False -> True
  }",
    )
}

pub fn extract_function_empty_body_test() {
  assert extract(
      FunctionBody("main"),
      "import gleam/result

pub fn main() {
}
",
    )
    == Ok("")
}

pub fn extract_type_test() {
  assert extract(
      TypeDefinition("Wibble"),
      "import gleam/result

type Wibble {
  Wibble
  Wobble
}
",
    )
    == Ok(
      "type Wibble {
  Wibble
  Wobble
}",
    )
}

pub fn extract_type_alias_test() {
  assert extract(
      TypeAlias("Wibble"),
      "import gleam/result

type Wibble = Wobble
",
    )
    == Ok("type Wibble = Wobble")
}

fn extract(segment: CodeSegment, source: String) -> Result(String, ExtractError) {
  let assert Ok(file) = code_extractor.load(source)
  code_extractor.extract(file, segment)
  |> result.map(caret.to_string)
}
