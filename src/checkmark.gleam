//// Keep code blocks in markdown files or Gleam comments up to date.

import checkmark/internal/code_extractor
import checkmark/internal/lines.{to_lines}
import checkmark/internal/parser.{type Fence}
import gleam/dict.{type Dict}
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/result
import gleam/string
import splitter

/// Contains the configuration for checking files.
/// Not tied to a single file.
/// The error type depends on the IO library used.
pub opaque type Checker(e) {
  Checker(
    read: fn(String) -> Result(String, e),
    write: fn(String, String) -> Result(Nil, e),
  )
}

/// A markdown or source file to check, which can be linked to snippets in multiple other files.
/// The error type depends on the IO library used.
pub opaque type File(e) {
  File(
    name: String,
    checker: Checker(e),
    check_in_comments: Bool,
    expectations: List(Expectation),
  )
}

/// A Gleam source file, from which snippets can be loaded.
pub opaque type CodeSnippetSource {
  CodeSnippetSource(filename: String, file: code_extractor.File)
}

/// Any error that can happen while using `checkmark`.
/// The error type depends on the IO library used.
pub type CheckError(e) {
  /// Could not read a source or target file.
  CouldNotReadFile(error: e)
  /// While updating, could not write a file.
  CouldNotWriteFile(error: e)
  /// Could not find a code snippet with the given tag.
  TagNotFound(tag: String)
  /// Found multiple code blocks with the same tag.
  MultipleTagsFound(tag: String, lines: List(Int))
  /// While checking, the content didn't match expectations.
  ContentDidNotMatch(tag: String)
  /// Could not load a code segment from a Gleam source file.
  FailedToLoadCodeSegment(file: String, reason: String)
  /// Could not parse a Gleam source file as a snippet source.
  CouldNotParseSnippetSource
}

type Expectation {
  ContentsOfFile(tag: String, filename: String)
  CodeSegment(
    tag: String,
    filename: String,
    file: code_extractor.File,
    segment: CodeSegment,
  )
}

type CodeSegment =
  code_extractor.CodeSegment

/// The full definition of the function with the given name.
pub fn function(name: String) -> CodeSegment {
  code_extractor.Function(name)
}

/// The body of the function with the given name.
/// Content is unindented based on the indentation of the first line.
pub fn function_body(name: String) -> CodeSegment {
  code_extractor.FunctionBody(name)
}

/// The full type definition of the type with the given name.
pub fn type_definition(name: String) -> CodeSegment {
  code_extractor.TypeDefinition(name)
}

/// A type alias definition
pub fn type_alias(name: String) -> CodeSegment {
  code_extractor.TypeAlias(name)
}

/// Builds a new checker with the provided file IO functions.
pub fn new(
  read_file: fn(String) -> Result(String, e),
  write_file: fn(String, String) -> Result(Nil, e),
) -> Checker(e) {
  Checker(read_file, write_file)
}

@deprecated("Use document instead")
pub fn file(checker: Checker(e), filename: String) -> File(e) {
  document(checker, filename)
}

/// Starts configuring a markdown file to be checked or updated.
/// See [`should_contain_contents_of`](#should_contain_contents_of)
/// and [`should_contain_snippet_from`](#should_contain_snippet_from)
/// to configure the content.
pub fn document(checker: Checker(e), filename: String) -> File(e) {
  File(filename, checker, False, [])
}

/// Starts configuring code blocks in comments of
/// a Gleam source file to be checked or updated.
/// See [`should_contain_contents_of`](#should_contain_contents_of)
/// and [`should_contain_snippet_from`](#should_contain_snippet_from)
/// to configure the content.
pub fn comments_in(checker: Checker(e), filename: String) -> File(e) {
  File(filename, checker, True, [])
}

/// Loads a Gleam source file to extract snippets from.
pub fn load_snippet_source(
  checker: Checker(e),
  filename: String,
) -> Result(CodeSnippetSource, CheckError(e)) {
  use content <- result.try(read_file(checker, filename))
  code_extractor.load(content)
  |> result.replace_error(CouldNotParseSnippetSource)
  |> result.map(CodeSnippetSource(filename, _))
}

/// Specify that the file should contain the contents of another file as a code block.
/// For example
///
/// ```gleam contents_of
/// checker
/// |> checkmark.document("README.md")
/// |> checkmark.should_contain_contents_of("./example.sh", tagged: "sh deps")
/// ```
///
/// will replace the code block starting with ```` ```sh deps````
/// with the contents of `example.sh`.
/// Whitespace is trimmed off the tag when matching it.
/// Note that you still need to call `check`, `update` or `check_or_update` after this -
/// this function only adds to the configuration.
pub fn should_contain_contents_of(
  file: File(e),
  filename: String,
  tagged tag: String,
) -> File(e) {
  File(..file, expectations: [
    ContentsOfFile(tag:, filename:),
    ..file.expectations
  ])
}

/// Specify that the file should contain a code snippet from another file.
/// For example
///
/// ```gleam snippet_from
/// checker
/// |> checkmark.document("README.md")
/// |> checkmark.should_contain_snippet_from(
///   snippets,
///   checkmark.function("wibble"),
///   tagged: "wibble",
/// )
/// ```
///
/// will replace the code block starting with ```` ```gleam wibble````
/// with the full definition of the `wibble` function.
/// Whitespace is trimmed off the tag when matching it.
/// Note that you still need to call `check`, `update` or `check_or_update` after this -
/// this function only adds to the configuration.
pub fn should_contain_snippet_from(
  file: File(e),
  source: CodeSnippetSource,
  segment: CodeSegment,
  tagged tag: String,
) -> File(e) {
  File(..file, expectations: [
    CodeSegment("gleam " <> tag, source.filename, source.file, segment),
    ..file.expectations
  ])
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

/// Checks that the target file contain the expected code blocks.
/// See [`should_contain_contents_of`](#should_contain_contents_of)
/// and [`should_contain_snippet_from`](#should_contain_snippet_from)
/// to configure the content.
pub fn check(file: File(e)) -> Result(Nil, List(CheckError(e))) {
  use contents <- result.try(parse_file(file))
  let results = {
    use expectation <- list.map(file.expectations)
    use lines <- result.try(get_expected_lines(file.checker, expectation))
    check_one(contents, lines, expectation.tag)
  }

  let #(_, errors) = result.partition(results)

  case errors {
    [] -> Ok(Nil)
    _ -> Error(errors)
  }
}

/// Updates the code blocks in the target file.
/// See [`should_contain_contents_of`](#should_contain_contents_of)
/// and [`should_contain_snippet_from`](#should_contain_snippet_from)
/// to configure the content.
pub fn update(file: File(e)) -> Result(Nil, List(CheckError(e))) {
  use contents <- result.try(parse_file(file))
  let results = {
    use expectation <- list.map(file.expectations)
    use lines <- result.try(get_expected_lines(file.checker, expectation))
    Ok(#(expectation.tag, lines))
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

fn get_expected_lines(
  checker: Checker(e),
  expectation: Expectation,
) -> Result(List(String), CheckError(e)) {
  case expectation {
    ContentsOfFile(filename:, ..) -> read_lines(checker, filename)
    CodeSegment(file:, segment:, ..) -> {
      code_extractor.extract(file, segment)
      |> result.map_error(fn(e) {
        let reason = case e {
          code_extractor.NameNotFound(name:) -> "Could not find " <> name
          code_extractor.SpanExtractionFailed ->
            "Extracting snippet failed, please report a bug!"
        }
        FailedToLoadCodeSegment(file: expectation.filename, reason:)
      })
    }
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
