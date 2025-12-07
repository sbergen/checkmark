import checkmark.{type Checker, CouldNotReadFile, MultipleTagsFound, TagNotFound}
import gleam/erlang/process
import gleeunit
import simplifile

pub fn main() {
  gleeunit.main()
}

pub fn check_existing_file_test() {
  assert checkmark.new(simplifile.read, simplifile.write)
    |> checkmark.document("./test/test.md")
    |> checkmark.should_contain_contents_of(
      "./test/test_content.txt",
      tagged: "multiple",
    )
    |> checkmark.should_contain_contents_of(
      "./test/test_content.txt",
      tagged: "single",
    )
    |> checkmark.should_contain_contents_of(
      "./test/test_content.txt",
      tagged: "not_present",
    )
    |> checkmark.check()
    == Error([MultipleTagsFound("multiple", [1, 6]), TagNotFound("not_present")])
}

pub fn check_missing_markdown_file_test() {
  assert checkmark.new(simplifile.read, simplifile.write)
    |> checkmark.document("this-file-does-not-exist")
    |> checkmark.check()
    == Error([CouldNotReadFile(simplifile.Enoent)])
}

pub fn check_missing_source_file_test() {
  assert checkmark.new(simplifile.read, simplifile.write)
    |> checkmark.document("./test/test.md")
    |> checkmark.should_contain_contents_of("this-file-does-not-exist", "")
    |> checkmark.check()
    == Error([CouldNotReadFile(simplifile.Enoent)])
}

pub fn update_markdown_test() {
  use checker <- update_test("./test/expected_updated.md")

  checker
  |> checkmark.document("./test/update.md")
  |> checkmark.should_contain_contents_of("./test/test_content.txt", "update")
  |> checkmark.update()
}

pub fn update_code_test() {
  use checker <- update_test("./test/expected_updated.gleam.txt")

  checker
  |> checkmark.comments_in("./test/test.gleam.txt")
  |> checkmark.should_contain_contents_of(
    "./test/test_content.txt",
    "gleam module",
  )
  |> checkmark.should_contain_contents_of(
    "./test/test_content.txt",
    "gleam value",
  )
  |> checkmark.update()
}

fn update_test(
  expected: String,
  using: fn(Checker(simplifile.FileError)) -> Result(Nil, a),
) -> Nil {
  let self = process.new_subject()
  let write = fn(_, content) {
    process.send(self, content)
    Ok(Nil)
  }

  assert using(checkmark.new(simplifile.read, write)) == Ok(Nil)

  let assert Ok(written) = process.receive(self, 0)
  let assert Ok(expected) = simplifile.read(expected)
  assert written == expected
}
