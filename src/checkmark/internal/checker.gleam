import checkmark.{type CheckError, type Operation}
import filepath
import gleam/io
import gleam/result.{try}
import gleam/string
import shellout
import simplifile
import temporary

const package_name = "checkmark_tmp"

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
      |> or(checkmark.CouldNotRun),
    )

    use _ <- try(
      simplifile.write(to: module_file, contents: code)
      |> result.map_error(fn(e) { checkmark.CouldNotRun(string.inspect(e)) }),
    )

    shellout.command(
      "gleam",
      with: to_args(operation),
      in: package_dir,
      opt: [],
    )
    |> or(checkmark.CheckFailed)
  }

  case file_result {
    Ok(r) -> r
    Error(e) -> Error(checkmark.CouldNotRun(string.inspect(e)))
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

fn to_args(op: checkmark.Operation) -> List(String) {
  case op {
    checkmark.Build -> ["build"]
    checkmark.Check -> ["check"]
    checkmark.Run -> ["run"]
  }
}
