import exception
import filepath
import gleam/function
import gleam/io
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/result.{try}
import gleam/string
import kirala/markdown/parser
import shellout
import simplifile
import temporary

/// Specifies the `gleam` CLI operation to run on each snippet
pub type Operation {
  /// Will run `gleam check` on the code
  Check
  /// Will run `gleam build` on the code
  Build
  /// Will run `gleam run` on the code
  Run
}

/// Indicates a check on an individual snippet failed
pub type CheckError {
  /// Running the check failed before we could get the result from `gleam`.
  /// The string value might currently be a bit cryptic, it should be improved.
  RunFailed(String)
  /// We were able to run the `gleam` operation, but it failed with the given output.
  CheckFailed(String)
}

/// Type alias for a result of checking a single snippet.
pub type CheckResult =
  Result(Nil, CheckError)

/// Configuration for checking a markdown file.
pub opaque type CheckConfig {
  CheckConfig(
    filename: String,
    filter: fn(String) -> Bool,
    operation: Operation,
  )
}

/// Constructs a new check configuration with the defaults of
/// running `gleam check` on all snippets in the README.md file.
pub fn new() -> CheckConfig {
  CheckConfig("README.md", fn(_) { True }, Check)
}

/// Specifies the markdown file to check (default is README.md)
pub fn snippets_in(config: CheckConfig, filename: String) -> CheckConfig {
  CheckConfig(..config, filename: filename)
}

/// Filters snippets by their content. E.g. `string.starts_with(_, "import")`
pub fn filtering(config: CheckConfig, filter: fn(String) -> Bool) -> CheckConfig {
  CheckConfig(..config, filter: filter)
}

/// Uses the given operation, default is `Check`
pub fn using(config: CheckConfig, operation: Operation) -> CheckConfig {
  CheckConfig(..config, operation: operation)
}

/// Runs checks in the current package,
/// writing into temporary file at `src/{filename}`.
/// The result will be `Error` if the whole operation failed (e.g. couldn't read snippets)
/// or `Ok` with a list of results for each snippet found in the file.
pub fn check_in_current_package(
  config: CheckConfig,
  as_file filename: String,
) -> Result(List(CheckResult), String) {
  use snippet <- check_snippets_in(config.filename, config.filter)
  check_in_dir(snippet, ".", filename, False, config.operation)
}

/// Runs checks in a temporarily set up package,
/// installing the given dependencies using `gleam add`.
/// The result will be `Error` if the whole operation failed (e.g. couldn't read snippets)
/// or `Ok` with a list of results for each snippet found in the file.
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

/// Prints errors to stderr, as using `panic` or `let assert`
/// doesn't usually print nicely on erlang
/// (the data is shown as binary,
/// as the compiler output contains lost non-ASCII characters).
/// Optionally panic, if `panic_if_failed` is `True`.
pub fn print_failures(
  result: Result(List(CheckResult), String),
  panic_if_failed panic_if_failed: Bool,
) -> Nil {
  let error_messages = case result {
    Ok(results) -> {
      case list.any(results, result.is_error) {
        True -> summarize_results(results)
        False -> None
      }
    }
    Error(error) -> Some("Failed to run: " <> error)
  }

  case error_messages {
    Some(errors) -> {
      io.println_error(errors)
      case panic_if_failed {
        True -> panic as "checkmark checks failed!"
        False -> Nil
      }
    }
    None -> Nil
  }
}

fn summarize_results(results: List(CheckResult)) -> Option(String) {
  Some({
    let indexed =
      list.range(1, list.length(results))
      |> list.zip(results)
    {
      use #(index, result) <- list.flat_map(indexed)

      let #(status, error) = case result {
        Error(e) ->
          case e {
            CheckFailed(e) -> #("Check failed!", Some(e))
            RunFailed(e) -> #("Failed to run check!", Some(e))
          }
        Ok(_) -> #("Check passed!", None)
      }

      [
        Some(""),
        Some("Snippet " <> string.inspect(index) <> ": " <> status),
        Some("-----------------------------------------"),
        error,
      ]
    }
    |> option.values
    |> string.join("\n")
  })
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
  case simplifile.create_file(path) {
    Error(simplifile.Eexist) if allow_overwrite -> Ok(Nil)
    Ok(_) -> Ok(Nil)
    Error(e) -> Error(RunFailed(string.inspect(e)))
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
