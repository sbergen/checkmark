import checkmark/internal/code_extractor.{
  Function, FunctionBody, TypeAlias, TypeDefinition,
}
import checkmark/internal/config.{CodeSegment, ContentsOfFile}
import gleam/dict
import simplifile

pub fn valid_config_test() {
  let assert Ok(toml) = simplifile.read("test/assets/config.toml")
  let assert Ok(config) = config.parse(toml)

  let expected =
    dict.from_list([
      #("README.md", [
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
      #("src/my_module.gleam", [
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

pub fn missing_target_keys_test() {
  assert config.parse("[document]\n")
    == Error([
      "Expected 'document.sources' to be specified",
      "Expected 'document.path' to be specified",
    ])
}

pub fn incomplete_sources_test() {
  assert config.parse(
      "[readme]
path = \"README.md\"

[[readme.sources]]
path = \"dev/example.gleam\"",
    )
    == Error(["'readme.sources[0]' should contain either 'tag' or 'snippets'."])
}

pub fn tag_and_snippets_test() {
  assert config.parse(
      "[readme]
path = \"README.md\"

[[readme.sources]]
path = \"dev/example.gleam\"
tag = \"tag\"
snippets = []",
    )
    == Error([
      "'readme.sources[0].tag' must not be specified together with 'snippets'",
    ])
}

pub fn empty_snippets_test() {
  let assert Ok(_) =
    config.parse(
      "[readme]
path = \"README.md\"

[[readme.sources]]
path = \"dev/example.gleam\"
snippets = []",
    )
    as "empty snippets is ok"
}

pub fn snippets_wrong_type_test() {
  assert config.parse(
      "[readme]
path = \"README.md\"

[[readme.sources]]
path = \"dev/example.gleam\"
snippets = \"foo\"",
    )
    == Error(["Expected 'readme.sources[0].snippets' to be Array, found String"])
}

pub fn path_and_tag_wront_type_test() {
  assert config.parse(
      "[readme]
path = \"README.md\"

[[readme.sources]]
path = 42
tag = 37",
    )
    == Error([
      "Expected 'readme.sources[0].tag' to be String, found Int",
      "Expected 'readme.sources[0].path' to be String, found Int",
    ])
}

pub fn snippet_empty_object_test() {
  assert config.parse(
      "[readme]
path = \"README.md\"

[[readme.sources]]
path = \"\" 
snippets = [{}]",
    )
    == Error([
      "Expected 'readme.sources[0].snippets[0].tag' to be specified",
      "'readme.sources[0].snippets[0]' must define exactly one of 'function', 'function_body', 'type', or 'type_alias'",
    ])
}

pub fn snippet_duplicate_kind_test() {
  assert config.parse(
      "[readme]
path = \"README.md\"

[[readme.sources]]
path = \"\" 
snippets = [{ tag = \"foo\", function = \"f\", type = \"t\" }]",
    )
    == Error([
      "'readme.sources[0].snippets[0]' must define exactly one of 'function', 'function_body', 'type', or 'type_alias'",
    ])
}
// TODO: reserve options as a top level table
