import checkmark
import filepath
import gleam/io
import gleam/string
import gleeunit
import gleeunit/should

pub fn main() {
  gleeunit.main()
}

const default_file = "checkmark_tmp.gleam"

pub fn check_our_readme_test() {
  let assert Ok([Ok(_)]) =
    checkmark.new() |> checkmark.check_in_current_package("checkmark_tmp.gleam")
}

pub fn check_ok_local_test() {
  let assert Ok([Ok(_)]) =
    checkmark.new()
    |> checkmark.snippets_in(test_asset("ok.md"))
    |> checkmark.check_in_current_package(default_file)
}

pub fn check_ok_isolated_test() {
  let assert Ok([Ok(_)]) =
    checkmark.new()
    |> checkmark.snippets_in(test_asset("ok.md"))
    |> checkmark.check_in_tmp_package(["filepath"])
}

pub fn check_local_overwrite_not_allowed() {
  let assert Ok([Error(_)]) =
    checkmark.new()
    |> checkmark.snippets_in(test_asset("ok.md"))
    |> checkmark.check_in_current_package("test_overwrite.gleam")
}

pub fn check_ok_and_failure_test() {
  let assert Ok([Ok(_), Error(checkmark.CheckFailed(_))]) =
    checkmark.new()
    |> checkmark.snippets_in(test_asset("ok_and_failure.md"))
    |> checkmark.check_in_current_package(default_file)
}

pub fn check_runtime_failure_local_test() {
  let assert Ok([Error(checkmark.CheckFailed(error))]) =
    checkmark.new()
    |> checkmark.using(checkmark.Run)
    |> checkmark.snippets_in(test_asset("runtime_failure.md"))
    |> checkmark.check_in_current_package(default_file)
  let assert True = string.contains(error, "My Panic")
}

pub fn check_runtime_failure_isolated_test() {
  let assert Ok([Error(checkmark.CheckFailed(error))]) =
    checkmark.new()
    |> checkmark.using(checkmark.Run)
    |> checkmark.snippets_in(test_asset("runtime_failure.md"))
    |> checkmark.check_in_tmp_package([])
  let assert True = string.contains(error, "My Panic")
}

pub fn check_type_failure_test() {
  let assert Ok([Error(checkmark.CheckFailed(error))]) =
    checkmark.new()
    |> checkmark.snippets_in(test_asset("type_failure.md"))
    |> checkmark.check_in_current_package(default_file)
  let assert True = string.contains(error, "Type mismatch")
}

pub fn check_filter_test() {
  let assert Ok([Ok(_)]) =
    checkmark.new()
    |> checkmark.snippets_in(test_asset("with_and_without_import.md"))
    |> checkmark.filtering(string.starts_with(_, "import"))
    |> checkmark.check_in_current_package(default_file)
}

fn test_asset(filename: String) -> String {
  filepath.join("test", filename)
}
