import exception
import filepath
import gleam/io
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
  CouldNotRun(String)
  CheckFailed(String)
}

pub fn check(
  in file: String,
  using dependencies: List(String),
  selecting filter: fn(String) -> Bool,
  operation operation: Operation,
) -> Result(List(Result(Nil, CheckError)), String) {
  use content <- try(
    simplifile.read(from: file) |> result.map_error(string.inspect),
  )

  Ok(
    extract_gleam_code(content, filter)
    |> list.map(check_code(_, dependencies, operation)),
  )
}

@internal
pub fn extract_gleam_code(
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

@internal
pub fn check_code(
  code: String,
  dependencies: List(String),
  operation: Operation,
) -> Result(Nil, CheckError) {
  let file_result = {
    use temp_dir <- temporary.create(temporary.directory())
    let package_dir = filepath.join(temp_dir, package_name)

    use _ <- try(run_gleam(
      in: temp_dir,
      with: ["new", package_name],
      fail_as: CouldNotRun,
    ))

    use _ <- try(case dependencies {
      [] -> Ok(Nil)
      _ ->
        run_gleam(
          in: package_dir,
          with: ["add", ..dependencies],
          fail_as: CouldNotRun,
        )
    })

    check_in_dir(code, package_dir, operation)
  }

  case file_result {
    Ok(r) -> r
    Error(e) -> Error(CouldNotRun(string.inspect(e)))
  }
}

fn check_in_dir(
  code: String,
  package_dir: String,
  operation: Operation,
) -> Result(Nil, CheckError) {
  let source_dir = filepath.join(package_dir, "src")
  let source_file = filepath.join(source_dir, package_name <> ".gleam")
  use file <- with_tempfile(source_file, True)

  use _ <- try(
    simplifile.write(to: file, contents: code)
    |> result.map_error(fn(e) { CouldNotRun(string.inspect(e)) }),
  )

  run_gleam(with: to_args(operation), in: package_dir, fail_as: CheckFailed)
}

fn with_tempfile(
  path: String,
  allow_overwrite: Bool,
  operation: fn(String) -> Result(Nil, CheckError),
) {
  use _ <- try(create_file(path, allow_overwrite))
  use <- exception.defer(fn() { simplifile.delete(path) })
  operation(path)
}

fn create_file(path: String, allow_overwrite: Bool) -> Result(Nil, CheckError) {
  case allow_overwrite, simplifile.create_file(path) {
    True, Error(simplifile.Eexist) -> Ok(Nil)
    _, Ok(_) -> Ok(Nil)
    _, e -> Error(CouldNotRun(string.inspect(e)))
  }
}

fn run_gleam(
  in directory: String,
  with args: List(String),
  fail_as make_error: fn(String) -> CheckError,
) -> Result(Nil, CheckError) {
  case shellout.command("gleam", with: args, in: directory, opt: []) {
    Ok(_) -> Ok(Nil)
    Error(#(_, e)) -> Error(make_error(e))
  }
}

fn to_args(op: Operation) -> List(String) {
  case op {
    Build -> ["build"]
    Check -> ["check"]
    Run -> ["run"]
  }
}
