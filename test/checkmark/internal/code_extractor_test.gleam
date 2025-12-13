import checkmark/internal/code_extractor.{
  type File, Function, FunctionBody, TypeAlias, TypeDefinition,
}

pub fn extract_function_test() {
  let module =
    load_module(
      "import gleam/result

pub fn main() {

  Ok(42)
}
",
    )

  assert code_extractor.extract(module, Function("main"))
    == Ok([
      "pub fn main() {\n",
      "\n",
      "  Ok(42)\n",
      "}\n",
    ])
}

pub fn extract_function_body_test() {
  let module =
    load_module(
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

  assert code_extractor.extract(module, FunctionBody("main"))
    == Ok([
      "case True {\n",
      "  True -> False\n",
      "// weird indent\n",
      "\n",
      "  False -> True\n",
      "}\n",
    ])
}

pub fn extract_function_empty_body_test() {
  let module =
    load_module(
      "import gleam/result

pub fn main() {
}
",
    )

  assert code_extractor.extract(module, FunctionBody("main")) == Ok([])
}

pub fn extract_type_test() {
  let module =
    load_module(
      "import gleam/result

type Wibble {
  Wibble
  Wobble
}
",
    )

  assert code_extractor.extract(module, TypeDefinition("Wibble"))
    == Ok([
      "type Wibble {\n",
      "  Wibble\n",
      "  Wobble\n",
      "}\n",
    ])
}

pub fn extract_type_alias_test() {
  let module =
    load_module(
      "import gleam/result

type Wibble = Wobble
",
    )

  assert code_extractor.extract(module, TypeAlias("Wibble"))
    == Ok(["type Wibble = Wobble\n"])
}

fn load_module(source: String) -> File {
  let assert Ok(file) = code_extractor.load(source)
  file
}
