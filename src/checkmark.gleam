import exception
import filepath
import gleam/function
import gleam/list
import gleam/result.{try}
import gleam/string
import kirala/markdown/parser
import shellout
import simplifile
import temporary

pub type Operation {
  Check
  Build
  Run
}

pub type CheckError {
  RunFailed(String)
  CheckFailed(String)
}

pub type CheckResult =
  Result(Nil, CheckError)

pub opaque type CheckConfig {
  CheckConfig(
    filename: String,
    filter: fn(String) -> Bool,
    operation: Operation,
  )
}

/// Constructs a new check configuration with the defaults of
/// running `gleam check` on all snippets in the README.md file
pub fn new() -> CheckConfig {
  CheckConfig("README.md", fn(_) { True }, Check)
}

pub fn snippets_in(config: CheckConfig, filename: String) -> CheckConfig {
  CheckConfig(..config, filename: filename)
}

pub fn filtering(config: CheckConfig, filter: fn(String) -> Bool) -> CheckConfig {
  CheckConfig(..config, filter: filter)
}

pub fn using(config: CheckConfig, operation: Operation) -> CheckConfig {
  CheckConfig(..config, operation: operation)
}

/// Runs checks in the current package, writing into the given filename in src.
/// The result will be Error if the whole operation failed (e.g. couldn't read snippets)
/// or Ok with a list of results for each snippet found in the file.
pub fn check_in_current_package(
  config: CheckConfig,
  as_file filename: String,
) -> Result(List(CheckResult), String) {
  use snippet <- check_snippets_in(config.filename, config.filter)
  check_in_dir(snippet, ".", filename, False, config.operation)
}

/// Runs checks in a temporarily set up package, installing the given dependencies.
/// The result will be Error if the whole operation failed (e.g. couldn't read snippets)
/// or Ok with a list of results for each snippet found in the file.
pub fn check_in_tmp_package(
  config: CheckConfig,
  dependencies: List(String),
) -> Result(List(CheckResult), String) {
  use temp_dir <- with_tempdir()
  use package_dir <- try(set_up_package(temp_dir, dependencies))
  use snippet <- check_snippets_in(config.filename, config.filter)
  check_in_dir(
    snippet,
    package_dir,
    package_name <> ".gleam",
    True,
    config.operation,
  )
}

fn set_up_package(
  tmp_dir: String,
  dependencies: List(String),
) -> Result(String, String) {
  use _ <- try(run_gleam(
    in: tmp_dir,
    with: ["new", package_name],
    fail_as: function.identity,
  ))

  let package_dir = filepath.join(tmp_dir, package_name)
  use _ <- try(case dependencies {
    [] -> Ok(Nil)
    _ ->
      run_gleam(
        in: package_dir,
        with: ["add", ..dependencies],
        fail_as: function.identity,
      )
  })

  Ok(package_dir)
}

fn check_snippets_in(
  filename: String,
  filter: fn(String) -> Bool,
  check: fn(String) -> CheckResult,
) -> Result(List(CheckResult), String) {
  use content <- try(
    simplifile.read(from: filename) |> result.map_error(string.inspect),
  )

  Ok(extract_gleam_code(content, filter) |> list.map(check))
}

fn extract_gleam_code(
  markdown: String,
  filter: fn(String) -> Bool,
) -> List(String) {
  let tokens = parser.parse_all(markdown)
  use token <- list.filter_map(tokens)
  case token {
    parser.CodeBlock("gleam", _, code) -> {
      case filter(code) {
        True -> Ok(code)
        _ -> Error(Nil)
      }
    }
    _ -> Error(Nil)
  }
}

const package_name = "checkmark_tmp"

fn check_in_dir(
  code: String,
  package_dir: String,
  filename: String,
  allow_overwrite: Bool,
  operation: Operation,
) -> CheckResult {
  let source_dir = filepath.join(package_dir, "src")
  let source_file = filepath.join(source_dir, filename)
  use file <- with_tempfile(source_file, allow_overwrite)

  use _ <- try(
    simplifile.write(to: file, contents: code)
    |> result.map_error(fn(e) { RunFailed(string.inspect(e)) }),
  )

  case string.split(filename, ".") {
    [] -> Error(CheckFailed("Invalid source file name: " <> filename))
    [module, ..] ->
      run_gleam(
        with: to_args(operation, module),
        in: package_dir,
        fail_as: CheckFailed,
      )
  }
}

fn with_tempdir(
  operation: fn(String) -> Result(List(CheckResult), String),
) -> Result(List(CheckResult), String) {
  {
    use temp_dir <- temporary.create(temporary.directory())
    operation(temp_dir)
  }
  |> result.map_error(string.inspect)
  |> result.flatten
}

fn with_tempfile(
  path: String,
  allow_overwrite: Bool,
  operation: fn(String) -> CheckResult,
) -> CheckResult {
  use _ <- try(create_file(path, allow_overwrite))
  use <- exception.defer(fn() { simplifile.delete(path) })
  operation(path)
}

fn create_file(path: String, allow_overwrite: Bool) -> CheckResult {
  case allow_overwrite, simplifile.create_file(path) {
    True, Error(simplifile.Eexist) -> Ok(Nil)
    _, Ok(_) -> Ok(Nil)
    _, e -> Error(RunFailed(string.inspect(e)))
  }
}

fn run_gleam(
  in directory: String,
  with args: List(String),
  fail_as make_error: fn(String) -> e,
) -> Result(Nil, e) {
  case shellout.command("gleam", with: args, in: directory, opt: []) {
    Ok(_) -> Ok(Nil)
    Error(#(_, e)) -> Error(make_error(e))
  }
}

fn to_args(op: Operation, module: String) -> List(String) {
  case op {
    Build -> ["build"]
    Check -> ["check"]
    Run -> ["run", "--module", module]
  }
}
