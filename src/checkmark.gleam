//// Link code in files with code blocks in markdown,
//// and check that they are up to date, or update them automatically.

import checkmark/internal/parser.{type Fence}
import gleam/dict.{type Dict}
import gleam/list
import gleam/option.{type Option}
import gleam/result
import gleam/string
import splitter

/// Contains the configuration for checking files.
/// Not tied to a single file, may contain more configuration later.
/// The error type depends on the IO library used.
pub opaque type Checker(e) {
  Checker(
    read: fn(String) -> Result(String, e),
    write: fn(String, String) -> Result(Nil, e),
  )
}

/// A markdown file to check, which can be linked to snippets in multiple other files.
/// The error type depends on the IO library used.
pub opaque type File(e) {
  File(name: String, checker: Checker(e), expectations: List(#(String, String)))
}

/// Any error that can happen during checking or updating a markdown file.
/// The error type depends on the IO library used.
pub type CheckError(e) {
  CouldNotReadFile(error: e)
  CouldNotWriteFile(error: e)
  TagNotFound(tag: String)
  MultipleTagsFound(tag: String, lines: List(Int))
  ContentDidNotMatch(tag: String)
}

/// Builds a new checker with the provided file IO functions.
pub fn new(
  read_file: fn(String) -> Result(String, e),
  write_file: fn(String, String) -> Result(Nil, e),
) -> Checker(e) {
  Checker(read_file, write_file)
}

/// Configures a markdown file to be checked or updated.
pub fn file(checker: Checker(e), filename: String) -> File(e) {
  File(filename, checker, [])
}

/// Specify that the markdown file should contain the contents of another file as a code block.
/// The tag is what comes after the block fence.
/// e.g. "```gleam 1" would match the tag "gleam 1".
/// Whitespace is trimmed off the tag.
/// Note that you still need to call `check`, `update` or `check_or_update` after this,
/// this function only adds to the configuration.
pub fn should_contain_contents_of(
  file: File(e),
  source: String,
  tagged tag: String,
) -> File(e) {
  File(..file, expectations: [#(source, tag), ..file.expectations])
}

/// Convenience function for either checking or updating depending on a boolean.
pub fn check_or_update(
  file: File(e),
  when should_update: Bool,
) -> Result(Nil, List(CheckError(e))) {
  case should_update {
    True -> update(file)
    False -> check(file)
  }
}

/// Checks that the markdown file contains code blocks that match the content of the specified files.
pub fn check(file: File(e)) -> Result(Nil, List(CheckError(e))) {
  use contents <- result.try(parse_file(file))
  let results = {
    use #(filename, tag) <- list.map(file.expectations)
    use expected <- result.try(read_file(file.checker, filename))
    check_one(contents, expected, tag)
  }

  let #(_, errors) = result.partition(results)

  case errors {
    [] -> Ok(Nil)
    _ -> Error(errors)
  }
}

/// Updates the code blocks in the markdown file from the specified files.
pub fn update(file: File(e)) -> Result(Nil, List(CheckError(e))) {
  use contents <- result.try(parse_file(file))
  let results = {
    use #(filename, tag) <- list.map(file.expectations)
    use _ <- result.try(find_match(contents, tag, []))
    use expected <- result.try(read_file(file.checker, filename))
    Ok(#(tag, expected))
  }

  let #(replacements, errors) = result.partition(results)

  case errors {
    [] -> {
      let contents = render_replacements(contents, dict.from_list(replacements))
      file.checker.write(file.name, contents)
      |> result.map_error(fn(e) { [CouldNotWriteFile(e)] })
    }
    _ -> Error(errors)
  }
}

fn render_replacements(
  contents: List(parser.Section),
  replacements: Dict(String, String),
) -> String {
  contents
  |> list.map(fn(section) {
    case section {
      parser.FencedCode(_, content, start_fence, end_fence) -> {
        case dict.get(replacements, string.trim(start_fence.info)) {
          Ok(replacement) -> render_code(start_fence, replacement, end_fence)
          Error(_) -> render_code(start_fence, content, end_fence)
        }
      }
      parser.Other(_, content) -> content
    }
  })
  |> string.join("")
}

fn render_code(
  start_fence: Fence,
  content: String,
  end_fence: Option(Fence),
) -> String {
  // This is not very optimized, but we probably don't need to care...

  let content = case start_fence.indent {
    0 -> content
    amount ->
      indent(
        splitter.new(["\n", "\r\n"]),
        string.repeat(" ", amount),
        content,
        [],
      )
  }

  let without_end = render_fence(start_fence) <> content
  case end_fence {
    option.None -> without_end
    option.Some(end_fence) -> without_end <> render_fence(end_fence)
  }
}

fn indent(
  line_ends: splitter.Splitter,
  with: String,
  rest: String,
  parts: List(String),
) -> String {
  case rest {
    "" -> parts |> list.reverse |> string.join("")
    _ -> {
      let #(content, ending, rest) = splitter.split(line_ends, rest)
      indent(line_ends, with, rest, [ending, content, with, ..parts])
    }
  }
}

fn render_fence(fence: Fence) -> String {
  string.repeat(" ", fence.indent) <> fence.fence <> fence.info
}

fn parse_file(
  file: File(e),
) -> Result(List(parser.Section), List(CheckError(e))) {
  read_file(file.checker, file.name)
  |> result.map_error(list.wrap)
  |> result.map(parser.parse(_, False))
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
  use snippet <- result.try(find_match(content, tag, []))
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
          find_match(rest, tag, [result, ..found])
        }
        False -> find_match(rest, tag, found)
      }
    }

    [_, ..rest] -> find_match(rest, tag, found)
  }
}
