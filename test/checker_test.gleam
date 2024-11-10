import checkmark
import gleam/string

pub fn check_code_no_error_test() {
  let code =
    "import gleam/io

pub fn main() {
  io.println(\"hello, friend!\")
}"

  let assert Ok(_) = checkmark.check_code(code, [], checkmark.Run)
}

pub fn check_code_type_error_test() {
  let code =
    "import gleam/list

pub fn main() {
  list.map([], 42)
}"

  let assert Error(checkmark.CheckFailed(e)) =
    checkmark.check_code(code, [], checkmark.Check)
  let assert True = string.contains(e, "Expected type")
}

pub fn check_code_runtime_error_test() {
  let code =
    "
pub fn main() {
  panic as \"My panic\"
}"

  let assert Error(checkmark.CheckFailed(e)) =
    checkmark.check_code(code, [], checkmark.Run)
  let assert True = string.contains(e, "My panic")
}

pub fn check_code_with_dependencies_test() {
  let code =
    "
import simplifile
import temporary

pub fn main() {
  panic as \"My panic\"
}"

  let assert Ok(_) =
    checkmark.check_code(code, ["simplifile", "temporary"], checkmark.Build)
}
