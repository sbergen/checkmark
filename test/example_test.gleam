import checkmark
import envoy
import simplifile

pub fn example_test() {
  assert checkmark.new(simplifile.read, simplifile.write)
    |> checkmark.document("README.md")
    |> checkmark.should_contain_contents_of("./example.sh", tagged: "sh")
    |> checkmark.should_contain_contents_of(
      "./test/example_test.gleam",
      tagged: "gleam",
    )
    // Update locally, check on CI
    |> checkmark.check_or_update(
      when: envoy.get("GITHUB_WORKFLOW") == Error(Nil),
    )
    == Ok(Nil)
}
