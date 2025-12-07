//// Link code in files with code blocks in markdown,
//// and check that they are up to date, or update them automatically.

import checkmark/internal/parser.{type Fence}
import gleam/dict.{type Dict}
import gleam/list
import gleam/option.{type Option, None, Some}
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
  File(
    name: String,
    checker: Checker(e),
    check_in_comments: Bool,
    expectations: List(#(String, String)),
  )
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
@deprecated("Use document instead")
pub fn file(checker: Checker(e), filename: String) -> File(e) {
  document(checker, filename)
}

/// Configures a markdown document to be checked or updated.
pub fn document(checker: Checker(e), filename: String) -> File(e) {
  File(filename, checker, False, [])
}

/// Configures comments in a gleam source file to be checked or updated.
pub fn comments_in(checker: Checker(e), filename: String) -> File(e) {
  File(filename, checker, True, [])
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
    use expected <- result.try(read_lines(file.checker, filename))
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
    use expected <- result.try(read_lines(file.checker, filename))
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
  replacements: Dict(String, List(String)),
) -> String {
  contents
  |> list.flat_map(fn(section) {
    case section {
      parser.FencedCode(lines:, start_fence:, end_fence:, prefix:, ..) -> {
        case dict.get(replacements, string.trim(start_fence.info)) {
          Ok(replacement) ->
            render_code(start_fence, prefix, replacement, end_fence)
          Error(_) -> render_code(start_fence, prefix, lines, end_fence)
        }
      }
      parser.Other(lines:, ..) -> lines
    }
  })
  |> string.join("")
}

fn render_code(
  start_fence: Fence,
  prefix: String,
  content: List(String),
  end_fence: Option(Fence),
) -> List(String) {
  let end_fence = option.map(end_fence, render_fence(prefix, _))
  let without_end_fence = case start_fence.indent, prefix, end_fence {
    0, "", None -> content
    0, "", Some(end_fence) -> list.append(content, [end_fence])
    amount, _, _ -> {
      let indent = prefix <> string.repeat(" ", amount)
      let content =
        content
        |> list.fold([], fn(lines, line) {
          [string.append(indent, line), ..lines]
        })

      let content = case end_fence {
        None -> content
        Some(fence) -> [fence, ..content]
      }

      list.reverse(content)
    }
  }

  [render_fence(prefix, start_fence), ..without_end_fence]
}

fn render_fence(prefix: String, fence: Fence) -> String {
  prefix <> string.repeat(" ", fence.indent) <> fence.fence <> fence.info
}

fn parse_file(
  file: File(e),
) -> Result(List(parser.Section), List(CheckError(e))) {
  read_lines(file.checker, file.name)
  |> result.map_error(list.wrap)
  |> result.map(parser.parse(_, file.check_in_comments))
}

fn read_file(
  checker: Checker(e),
  filename: String,
) -> Result(String, CheckError(e)) {
  checker.read(filename)
  |> result.map_error(CouldNotReadFile)
}

fn read_lines(
  checker: Checker(e),
  filename: String,
) -> Result(List(String), CheckError(e)) {
  use content <- result.map(read_file(checker, filename))
  splitter.new(["\n", "\r\n"]) |> to_lines(content, [])
}

fn to_lines(
  splitter: splitter.Splitter,
  content: String,
  lines: List(String),
) -> List(String) {
  let #(line, rest) = splitter.split_after(splitter, content)
  let lines = [line, ..lines]
  case rest {
    "" -> list.reverse(lines)
    _ -> to_lines(splitter, rest, lines)
  }
}

fn check_one(
  content: List(parser.Section),
  expected: List(String),
  tag: String,
) -> Result(Nil, CheckError(e)) {
  use snippet <- result.try(find_match(content, tag, []))
  case snippet.content == expected {
    True -> Ok(Nil)
    False -> Error(ContentDidNotMatch(tag))
  }
}

type Snippet {
  Snippet(content: List(String), start_fence: Fence, end_fence: Option(Fence))
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

    [
      parser.FencedCode(line_number:, lines:, start_fence:, end_fence:, ..),
      ..rest
    ] -> {
      case string.trim(start_fence.info) == tag {
        True -> {
          let result = #(line_number, Snippet(lines, start_fence, end_fence))
          find_match(rest, tag, [result, ..found])
        }
        False -> find_match(rest, tag, found)
      }
    }

    [_, ..rest] -> find_match(rest, tag, found)
  }
}
