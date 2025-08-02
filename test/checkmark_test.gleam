import checkmark.{CouldNotReadFile, MultipleTagsFound, TagNotFound}
import gleeunit
import simplifile

pub fn main() {
  gleeunit.main()
}

pub fn check_existing_file_test() {
  assert checkmark.new(simplifile.read, simplifile.write)
    |> checkmark.file("./test/test.md")
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
    |> checkmark.file("this-file-does-not-exist")
    |> checkmark.check()
    == Error([CouldNotReadFile(simplifile.Enoent)])
}

pub fn check_missing_source_file_test() {
  assert checkmark.new(simplifile.read, simplifile.write)
    |> checkmark.file("./test/test.md")
    |> checkmark.should_contain_contents_of("this-file-does-not-exist", "")
    |> checkmark.check()
    == Error([CouldNotReadFile(simplifile.Enoent)])
}
