import filepath
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
    let module_file =
      filepath.join(package_dir, "src")
      |> filepath.join(package_name <> ".gleam")

    use _ <- try(
      shellout.command(
        "gleam",
        with: ["new", package_name],
        in: temp_dir,
        opt: [],
      )
      |> or(CouldNotRun),
    )

    use _ <- try(case dependencies {
      [] -> Ok(Nil)
      _ -> {
        shellout.command(
          "gleam",
          with: ["add", ..dependencies],
          in: package_dir,
          opt: [],
        )
        |> or(CouldNotRun)
      }
    })

    use _ <- try(
      simplifile.write(to: module_file, contents: code)
      |> result.map_error(fn(e) { CouldNotRun(string.inspect(e)) }),
    )

    shellout.command(
      "gleam",
      with: to_args(operation),
      in: package_dir,
      opt: [],
    )
    |> or(CheckFailed)
  }

  case file_result {
    Ok(r) -> r
    Error(e) -> Error(CouldNotRun(string.inspect(e)))
  }
}

fn or(
  r: Result(String, #(Int, String)),
  make_error: fn(String) -> CheckError,
) -> Result(Nil, CheckError) {
  case r {
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
