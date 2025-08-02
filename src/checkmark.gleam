import checkmark/internal/parser.{type Fence}
import gleam/list
import gleam/option.{type Option}
import gleam/result
import gleam/string

pub opaque type Checker(e) {
  Checker(
    read: fn(String) -> Result(String, e),
    write: fn(String, String) -> Result(Nil, e),
  )
}

pub opaque type File(e) {
  File(name: String, checker: Checker(e), expectations: List(#(String, String)))
}

pub type CheckError(e) {
  CouldNotReadFile(error: e)
  CouldNotWriteFile(error: e)
  TagNotFound(tag: String)
  MultipleTagsFound(tag: String, lines: List(Int))
  ContentDidNotMatch(tag: String)
}

pub fn new(
  read_file: fn(String) -> Result(String, e),
  write_file: fn(String, String) -> Result(Nil, e),
) -> Checker(e) {
  Checker(read_file, write_file)
}

pub fn file(checker: Checker(e), filename: String) -> File(e) {
  File(filename, checker, [])
}

pub fn should_contain_contents_of(
  file: File(e),
  source: String,
  tagged tag: String,
) -> File(e) {
  File(..file, expectations: [#(source, tag), ..file.expectations])
}

pub fn check(file: File(e)) -> Result(Nil, List(CheckError(e))) {
  use content <- result.try(
    read_file(file.checker, file.name)
    |> result.map_error(list.wrap),
  )

  let content = parser.parse(content)

  let results = {
    use #(filename, tag) <- list.map(file.expectations)
    use expected <- result.try(read_file(file.checker, filename))
    check_one(content, expected, tag)
  }

  let #(_, errors) = result.partition(results)

  case errors {
    [] -> Ok(Nil)
    _ -> Error(errors)
  }
}

fn read_file(
  checker: Checker(e),
  filename: String,
) -> Result(String, CheckError(e)) {
  checker.read(filename) |> result.map_error(CouldNotReadFile)
}

fn check_one(
  content: List(parser.Section),
  expected: String,
  tag: String,
) -> Result(Nil, CheckError(e)) {
  use snippet <- result.try(find_match(content, expected, tag, []))
  case snippet.content == expected {
    True -> Ok(Nil)
    False -> Error(ContentDidNotMatch(tag))
  }
}

type Snippet {
  Snippet(content: String, start_fence: Fence, end_fence: Option(Fence))
}

fn find_match(
  content: List(parser.Section),
  expected: String,
  tag: String,
  found: List(#(Int, Snippet)),
) -> Result(Snippet, CheckError(e)) {
  case content {
    [] ->
      case found {
        [] -> Error(TagNotFound(tag))
        [#(_, snippet)] -> Ok(snippet)
        _ ->
          Error(MultipleTagsFound(
            tag,
            found |> list.reverse |> list.map(fn(pair) { pair.0 }),
          ))
      }

    [parser.FencedCode(line, content, start_fence, end_fence), ..rest] -> {
      case string.trim(start_fence.info) == tag {
        True -> {
          let result = #(line, Snippet(content, start_fence, end_fence))
          find_match(rest, expected, tag, [result, ..found])
        }
        False -> find_match(rest, expected, tag, found)
      }
    }

    [_, ..rest] -> find_match(rest, expected, tag, found)
  }
}
