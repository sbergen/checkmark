import checkmark
import simplifile

pub fn example_test() {
  assert checkmark.new(simplifile.read, simplifile.write)
    |> checkmark.file("README.md")
    |> checkmark.should_contain_contents_of("./example.sh", tagged: "sh")
    |> checkmark.should_contain_contents_of(
      "./test/example_test.gleam",
      tagged: "gleam",
    )
    |> checkmark.check()
    == Ok(Nil)
}
