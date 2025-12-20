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
  MultipleTagsFound(filename: String, tag: String, lines: List(Int))
  /// While checking, the content didn't match expectations.
  ContentDidNotMatch(tag: String)
  /// Could not parse a Gleam source file as a snippet source.
  CouldNotParseSnippetSource(file: String)

  // New ones
  InputNotProvided(filename: String)
  SnippetNotFound(file: String, name: String)
  CouldNotLoadSnippet(file: String, name: String)

  // TODO: Make this better?
  CodeFileError
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
  let #(code_files, errors) = load_snippets(config, inputs)
  let splitter = splitter.new(["\n", "\r\n"])
  let inputs = ReplaceInputs(splitter, inputs, code_files)

  let results = {
    use results, filename, expectations <- dict.fold(config, list.new())
    [get_file_replacements(inputs, filename, expectations), ..results]
  }

  let #(results, new_errors) = result.partition(results)
  let errors = list.append(errors, new_errors)

  // Fold the inner errors into the outer errors
  {
    use #(replacements, errors), #(replacement, new_errors) <- list.fold(
      results,
      #(list.new(), errors),
    )
    #([replacement, ..replacements], list.append(errors, new_errors))
  }
}

type ReplaceInputs {
  ReplaceInputs(
    /// Splitter to be reused
    splitter: splitter.Splitter,
    /// Contents of input files
    input_files: Dict(String, String),
    /// Parsed Gleam files (we parse them only once)
    code_files: Dict(String, code_extractor.File),
  )
}

fn load_snippets(
  config: Config,
  inputs: Dict(String, String),
) -> #(Dict(String, code_extractor.File), List(CheckError)) {
  use #(code_files, errors), filename <- set.fold(snippet_files(config), #(
    dict.new(),
    list.new(),
  ))

  case dict.get(inputs, filename) {
    Error(Nil) -> #(code_files, [InputNotProvided(filename), ..errors])
    Ok(content) ->
      case code_extractor.load(content) {
        Error(_) -> #(code_files, [
          CouldNotParseSnippetSource(filename),
          ..errors
        ])
        Ok(file) -> #(dict.insert(code_files, filename, file), errors)
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

// Get replacements for the file.
// It can either fail entirely, or produce replacements and errors.
fn get_file_replacements(
  inputs: ReplaceInputs,
  filename: String,
  expectations: List(Expectation),
) -> Result(#(FileReplacements, List(CheckError)), CheckError) {
  use content <- result.try(
    dict.get(inputs.input_files, filename)
    |> result.replace_error(InputNotProvided(filename)),
  )
  let lines = lines.to_lines(inputs.splitter, content, [])
  let sections = {
    let search_in_comments = string.ends_with(filename, ".gleam")
    parser.parse(lines, search_in_comments)
  }

  let #(replacements, errors) =
    expectations
    |> list.map(create_replacement(inputs, filename, sections, _))
    |> result.partition

  Ok(#(FileReplacements(filename, lines, replacements), errors))
}

fn create_replacement(
  inputs: ReplaceInputs,
  filename: String,
  sections: List(parser.Section),
  expectation: Expectation,
) -> Result(Replacement, CheckError) {
  use lines <- result.try(case expectation {
    config.ContentsOfFile(filename:, ..) ->
      dict.get(inputs.input_files, filename)
      |> result.replace_error(InputNotProvided(filename))
      |> result.map(lines.to_lines(inputs.splitter, _, []))

    config.CodeSegment(filename:, segment:, ..) ->
      dict.get(inputs.code_files, filename)
      // This was either a missing input or parsing failed,
      // we don't know at this point.
      |> result.replace_error(CodeFileError)
      |> result.try(fn(code_file) {
        code_extractor.extract(code_file, segment)
        |> result.replace_error(CouldNotLoadSnippet(filename, segment.name))
      })
  })

  let sections =
    list.filter(sections, fn(section) {
      case section {
        parser.FencedCode(start_fence: fence, ..) ->
          string.trim(fence.info) == expectation.tag
        _ -> False
      }
    })

  case sections {
    [section] -> {
      let line_count = list.length(section.lines)
      Ok(Replacement(
        section.line_number,
        section.line_number + line_count,
        lines,
      ))
    }

    [] -> Error(TagNotFound(filename, expectation.tag))

    sections -> {
      let lines = list.map(sections, fn(section) { section.line_number })
      Error(MultipleTagsFound(filename, expectation.tag, lines))
    }
  }
}
