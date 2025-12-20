//// Keep code blocks in markdown files or Gleam comments up to date.

import checkmark/internal/code_extractor.{type ExtractError}
import checkmark/internal/config.{type Config, type Expectation}
import checkmark/internal/lines
import checkmark/internal/parser
import gleam/dict.{type Dict}
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/result
import gleam/set.{type Set}
import gleam/string
import simplifile
import splitter

/// The configuration to use to check or update files
pub opaque type Configuration {
  Configuration(expectations: Dict(String, List(Expectation)))
}

pub fn new() -> Configuration {
  Configuration(dict.new())
}

pub fn parse_configuration(
  filename: String,
) -> Result(Configuration, List(String)) {
  config.parse(filename)
  |> result.map(Configuration)
}

/// Any error that can happen while using `checkmark`.
/// The error type depends on the IO library used.
pub type CheckError {
  /// Could not read a source or target file.
  CouldNotReadFile(error: simplifile.FileError)
  /// While updating, could not write a file.
  CouldNotWriteFile(error: simplifile.FileError)
  /// Could not find a code snippet with the given tag.
  TagNotFound(filename: String, tag: String)
  /// Found multiple code blocks with the same tag.
  MultipleTagsFound(tag: String, lines: List(Int))
  /// While checking, the content didn't match expectations.
  ContentDidNotMatch(tag: String)
  /// Could not parse a Gleam source file as a snippet source.
  CouldNotParseSnippetSource(file: String)

  // New ones
  InputNotProvided(filename: String)
  SnippetNotFound(file: String, name: String)
  CouldNotLoadSnippet(file: String, name: String)
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

pub opaque type ExpectationBuilder {
  ExpectationBuilder(filename: String, expectations: List(Expectation))
}

@deprecated("Use document instead")
pub fn file(
  configuration: Configuration,
  filename: String,
  configure: fn(ExpectationBuilder) -> ExpectationBuilder,
) -> Configuration {
  document(configuration, filename, configure)
}

/// Starts configuring a markdown file to be checked or updated.
/// See [`should_contain_contents_of`](#should_contain_contents_of)
/// and [`should_contain_snippet_from`](#should_contain_snippet_from)
/// to configure the content.
pub fn document(
  configuration: Configuration,
  filename: String,
  configure: fn(ExpectationBuilder) -> ExpectationBuilder,
) -> Configuration {
  // TODO: Check if file is already configured
  let builder = configure(ExpectationBuilder(filename, list.new()))
  Configuration(expectations: dict.insert(
    configuration.expectations,
    builder.filename,
    builder.expectations,
  ))
}

/// Starts configuring code blocks in comments of
/// a Gleam source file to be checked or updated.
/// See [`should_contain_contents_of`](#should_contain_contents_of)
/// and [`should_contain_snippet_from`](#should_contain_snippet_from)
/// to configure the content.
pub fn comments_in(
  configuration: Configuration,
  filename: String,
  configure: fn(ExpectationBuilder) -> ExpectationBuilder,
) -> Configuration {
  // TODO: Check if file is already configured
  let builder = configure(ExpectationBuilder(filename, list.new()))
  Configuration(dict.insert(
    configuration.expectations,
    builder.filename,
    builder.expectations,
  ))
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
  builder: ExpectationBuilder,
  filename: String,
  tagged tag: String,
) -> ExpectationBuilder {
  let expectation = config.ContentsOfFile(tag, filename)
  ExpectationBuilder(..builder, expectations: [
    expectation,
    ..builder.expectations
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
  builder: ExpectationBuilder,
  filename: String,
  segment: CodeSegment,
  tagged tag: String,
) -> ExpectationBuilder {
  let expectation = config.CodeSegment(tag, filename, segment)
  ExpectationBuilder(..builder, expectations: [
    expectation,
    ..builder.expectations
  ])
}

/// Convenience function for either checking or updating depending on a boolean.
pub fn check_or_update(
  configuration: Configuration,
  when should_update: Bool,
) -> Result(Nil, List(CheckError)) {
  case should_update {
    True -> update(configuration)
    False -> check(configuration)
  }
}

/// Checks that the target files contain the expected code blocks.
/// See [`should_contain_contents_of`](#should_contain_contents_of)
/// and [`should_contain_snippet_from`](#should_contain_snippet_from)
/// to configure the content.
pub fn check(configuration: Configuration) -> Result(Nil, List(CheckError)) {
  let inputs = {
    use inputs, filename <- set.fold(
      input_files(configuration.expectations),
      dict.new(),
    )

    // TODO handle errors
    let assert Ok(contents) = simplifile.read(echo filename)
    dict.insert(inputs, filename, contents)
  }

  let #(replacements, errors) =
    get_replacements(configuration.expectations, inputs)
  case errors, replacements {
    // TODO: Check that replacement is needed when building them
    [], [] -> Ok(Nil)
    [], replacements -> Error(todo)

    // TODO: also list found replacements as errors
    errors, _ -> Error(errors)
  }
}

/// Updates the code blocks in the target file.
/// See [`should_contain_contents_of`](#should_contain_contents_of)
/// and [`should_contain_snippet_from`](#should_contain_snippet_from)
/// to configure the content.
pub fn update(configuration: Configuration) -> Result(Nil, List(CheckError)) {
  todo
}

/// Replacements in a single file
pub type FileReplacements {
  FileReplacements(
    filename: String,
    lines: List(String),
    replacements: List(Replacement),
  )
}

/// A single replacement within a file
pub type Replacement {
  Replacement(from_line: Int, to_line: Int, new_lines: List(String))
}

/// Calculates the input files for the given configuration.
pub fn input_files(config: Config) -> Set(String) {
  use inputs, filename, expectations <- dict.fold(config, set.new())
  let inputs = set.insert(inputs, filename)

  use inputs, expectation <- list.fold(expectations, inputs)
  set.insert(inputs, expectation.filename)
}

pub fn get_replacements(
  config: Config,
  inputs: Dict(String, String),
) -> #(List(FileReplacements), List(CheckError)) {
  let state =
    new_state(inputs)
    |> load_snippets(config)

  let state = {
    use state, filename, expectations <- dict.fold(config, state)
    get_file_replacements(state, filename, expectations)
  }

  #(state.replacements, set.to_list(state.errors))
}

/// Helper record for incrementally building state
type ReplaceState {
  ReplaceState(
    /// Splitter to be reused
    splitter: splitter.Splitter,
    /// Contents of input files
    inputs: Dict(String, String),
    /// Parsed Gleam files (we parse them only once)
    code_files: Dict(String, code_extractor.File),
    /// Successful replacements
    replacements: List(FileReplacements),
    /// Found errors
    errors: Set(CheckError),
  )
}

/// Missing
fn new_state(inputs: Dict(String, String)) -> ReplaceState {
  let splitter = splitter.new(["\n", "\r\n"])
  ReplaceState(splitter, inputs, dict.new(), list.new(), set.new())
}

fn add_code_file(
  state: ReplaceState,
  filename: String,
  file: code_extractor.File,
) -> ReplaceState {
  ReplaceState(
    ..state,
    code_files: dict.insert(state.code_files, filename, file),
  )
}

fn add_replacments(
  state: ReplaceState,
  replacements: FileReplacements,
) -> ReplaceState {
  ReplaceState(..state, replacements: [replacements, ..state.replacements])
}

fn add_missing_input(state: ReplaceState, input: String) -> ReplaceState {
  ReplaceState(
    ..state,
    errors: set.insert(state.errors, InputNotProvided(input)),
  )
}

fn use_input(
  state: ReplaceState,
  input: String,
  then: fn(String) -> ReplaceState,
) -> ReplaceState {
  case dict.get(state.inputs, input) {
    Error(Nil) -> add_missing_input(state, input)
    Ok(content) -> then(content)
  }
}

fn add_invalid_code(state: ReplaceState, input: String) -> ReplaceState {
  ReplaceState(
    ..state,
    errors: set.insert(state.errors, CouldNotParseSnippetSource(input)),
  )
}

fn add_invalid_segment(
  state: ReplaceState,
  filename: String,
  error: ExtractError,
) -> ReplaceState {
  let error = case error {
    code_extractor.NameNotFound(name:) -> SnippetNotFound(filename, name)
    code_extractor.SpanExtractionFailed(name:) ->
      CouldNotLoadSnippet(filename, name)
  }
  ReplaceState(..state, errors: set.insert(state.errors, error))
}

fn get_file_replacements(
  state: ReplaceState,
  filename: String,
  expectations: List(Expectation),
) -> ReplaceState {
  use content <- use_input(state, filename)
  let lines = lines.to_lines(state.splitter, content, [])
  let sections = {
    let search_in_comments = string.ends_with(filename, ".gleam")
    parser.parse(lines, search_in_comments)
  }

  let #(state, replacements) = {
    use #(state, replacements), expectation <- list.fold(expectations, #(
      state,
      list.new(),
    ))

    let #(state, replacement) = create_replacement(state, sections, expectation)
    let #(state, replacements) = case replacement {
      Ok(replacement) -> #(state, [replacement, ..replacements])
      Error(Nil) -> #(
        ReplaceState(
          ..state,
          errors: set.insert(
            state.errors,
            TagNotFound(filename, expectation.tag),
          ),
        ),
        replacements,
      )
    }
    #(state, replacements)
  }

  add_replacments(state, FileReplacements(filename, lines, replacements))
}

fn create_replacement(
  state: ReplaceState,
  sections: List(parser.Section),
  expectation: Expectation,
) -> #(ReplaceState, Result(Replacement, Nil)) {
  let #(state, lines) = case expectation {
    config.CodeSegment(filename:, segment:, ..) ->
      get_code_segment(state, filename, segment)

    config.ContentsOfFile(filename:, ..) -> get_file_content(state, filename)
  }

  // Errors are added to the state already above, so they can be ignored here.
  // Also, the missing tag can only be reported by the caller.
  let replacement =
    result.try(lines, build_replacement(sections, expectation.tag, _))
  #(state, replacement)
}

// Build a replacement or return an error if the target was not found.
fn build_replacement(
  sections: List(parser.Section),
  tag: String,
  replacement: List(String),
) -> Result(Replacement, Nil) {
  let sections =
    list.filter(sections, fn(section) {
      case section {
        parser.FencedCode(start_fence: fence, ..) ->
          string.trim(fence.info) == tag
        _ -> False
      }
    })

  case sections {
    [section] -> {
      let line_count = list.length(section.lines)
      Ok(Replacement(
        section.line_number,
        section.line_number + line_count,
        replacement,
      ))
    }

    // TODO error for multiple matches
    _ -> Error(Nil)
  }
}

fn get_file_content(
  state: ReplaceState,
  filename: String,
) -> #(ReplaceState, Result(List(String), Nil)) {
  case dict.get(state.inputs, filename) {
    Error(Nil) -> #(add_missing_input(state, filename), Error(Nil))
    Ok(content) -> #(state, Ok(lines.to_lines(state.splitter, content, [])))
  }
}

fn get_code_segment(
  state: ReplaceState,
  filename: String,
  segment: CodeSegment,
) -> #(ReplaceState, Result(List(String), Nil)) {
  case dict.get(state.code_files, filename) {
    // If this missing, the error was reported already earlier, do nothing.
    Error(Nil) -> #(state, Error(Nil))

    Ok(code_file) ->
      case code_extractor.extract(code_file, segment) {
        Ok(lines) -> #(state, Ok(lines))
        Error(e) -> #(add_invalid_segment(state, filename, e), Error(Nil))
      }
  }
}

fn load_snippets(state: ReplaceState, config: Config) -> ReplaceState {
  use state, filename <- set.fold(snippet_files(config), state)

  case dict.get(state.inputs, filename) {
    Error(Nil) -> add_missing_input(state, filename)
    Ok(content) ->
      case code_extractor.load(content) {
        Error(_) -> add_invalid_code(state, filename)
        Ok(file) -> add_code_file(state, filename, file)
      }
  }
}

fn snippet_files(config: Config) -> Set(String) {
  use result, _filename, expectations <- dict.fold(config, set.new())
  use result, expectation <- list.fold(expectations, result)

  case expectation {
    config.CodeSegment(filename:, ..) -> set.insert(result, filename)
    config.ContentsOfFile(..) -> result
  }
}
