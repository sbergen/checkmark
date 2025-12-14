import checkmark/config.{CodeSegment, ContentsOfFile, Target}
import checkmark/internal/code_extractor.{
  Function, FunctionBody, TypeAlias, TypeDefinition,
}
import gleam/dict
import simplifile

pub fn valid_config_test() {
  let assert Ok(toml) = simplifile.read("test/assets/config.toml")
  let assert Ok(config) = config.parse(toml)

  let expected =
    dict.from_list([
      #(Target("readme", "README.md"), [
        CodeSegment(
          "type",
          "dev/readme_snippets.gleam",
          TypeDefinition("MyType"),
        ),
        CodeSegment(
          "function",
          "dev/readme_snippets.gleam",
          Function("my_function"),
        ),
        ContentsOfFile("sh file", "setup.sh"),
        ContentsOfFile("gleam file", "dev/readme_example.gleam"),
      ]),
      #(Target("my_module", "src/my_module.gleam"), [
        CodeSegment(
          "type alias",
          "dev/my_module_docs.gleam",
          TypeAlias("MyType"),
        ),
        CodeSegment(
          "function body",
          "dev/my_module_docs.gleam",
          FunctionBody("my_function"),
        ),
      ]),
    ])

  assert config == expected
}
// TODO: reserve options as a top level table
