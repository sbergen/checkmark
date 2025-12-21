//// Keep code blocks in markdown files or Gleam comments up to date.

import checkmark/internal/code_extractor
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

pub type CheckErrors {
  CheckErrors(
    file_errors: List(#(String, simplifile.FileError)),
    content_errors: List(ContentError),
  )
}

/// An error indicating that the content in the files or in the configuration
/// did not match the criteria for resolving what is expected or should be replaced.
pub type ContentError {
  /// Could not find a code block with the given tag.
  TagNotFound(filename: String, tag: String)
  /// Found multiple code blocks with the same tag.
  MultipleTagsFound(filename: String, tag: String, lines: List(Int))
  /// Could not parse a Gleam source file as a snippet source.
  CouldNotParseSnippetSource(file: String)
  /// The snippet could not be found
  CouldNotFindSnippet(file: String, name: String)
  /// The snippet could not be loaded. This is likely an issue in checkmark!
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
  // TODO: Check if file is already configured?
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
  // TODO: should we explicitly specify the document type?
  document(configuration, filename, configure)
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
) -> Result(Nil, CheckErrors) {
  case should_update {
    True -> update(configuration)
    False -> check(configuration)
  }
}

/// Checks that the target files contain the expected code blocks.
/// See [`should_contain_contents_of`](#should_contain_contents_of)
/// and [`should_contain_snippet_from`](#should_contain_snippet_from)
/// to configure the content.
pub fn check(configuration: Configuration) -> Result(Nil, CheckErrors) {
  case get_replacements_from_files(configuration) {
    // TODO: Check that replacement is needed when building them
    #([], [], []) -> Ok(Nil)

    #(_, file_errors, errors) -> Error(CheckErrors(file_errors, errors))
  }
}

/// Updates the code blocks in the target file.
/// See [`should_contain_contents_of`](#should_contain_contents_of)
/// and [`should_contain_snippet_from`](#should_contain_snippet_from)
/// to configure the content.
pub fn update(configuration: Configuration) -> Result(Nil, CheckErrors) {
  update_with_writer(configuration, simplifile.write)
}

@internal
pub fn update_with_writer(
  configuration: Configuration,
  write: fn(String, String) -> Result(Nil, simplifile.FileError),
) -> Result(Nil, CheckErrors) {
  let #(replacements, file_errors, errors) =
    get_replacements_from_files(configuration)

  let results = {
    use replacement <- list.map(replacements)
    let new_content = render_file(replacement)
    write(replacement.filename, new_content)
    |> result.map_error(fn(e) { #(replacement.filename, e) })
  }

  let #(_, new_errors) = result.partition(results)
  let file_errors = list.append(file_errors, new_errors)

  case errors, file_errors {
    [], [] -> Ok(Nil)
    _, _ -> Error(CheckErrors(file_errors, errors))
  }
}

fn get_replacements_from_files(
  configuration: Configuration,
) -> #(
  List(FileReplacements),
  List(#(String, simplifile.FileError)),
  List(ContentError),
) {
  let #(inputs, file_errors) = {
    use #(inputs, errors), filename <- set.fold(
      input_files(configuration.expectations),
      #(dict.new(), list.new()),
    )

    case simplifile.read(filename) {
      Ok(contents) -> #(dict.insert(inputs, filename, contents), errors)
      Error(e) -> #(inputs, [#(filename, e), ..errors])
    }
  }

  let #(replacements, errors) =
    get_replacements(configuration.expectations, inputs)

  #(replacements, file_errors, errors)
}

/// Replacements in a single file
pub type FileReplacements {
  FileReplacements(
    /// The file the replacements apply to.
    filename: String,
    /// The old lines in the file.
    lines: List(String),
    /// The replacements that should be made in the file.
    replacements: List(Replacement),
  )
}

/// A single replacement within a file
pub type Replacement {
  Replacement(from_line: Int, to_line: Int, new_lines: List(String))
}

fn render_file(replacements: FileReplacements) -> String {
  let FileReplacements(lines:, replacements:, ..) = replacements
  let replacements = {
    use replacements, replacement <- list.fold(replacements, dict.new())
    dict.insert(replacements, replacement.from_line, replacement)
  }

  let #(result, _) = {
    use #(result, skip_until), line, index <- list.index_fold(lines, #("", None))
    case skip_until {
      Some(skip_until) if skip_until == index -> #(result, None)

      None -> {
        case dict.get(replacements, index) {
          Ok(Replacement(to_line:, new_lines:, ..)) -> {
            let result = list.fold(new_lines, result, string.append)
            case to_line - 1 == index {
              // TODO: Zero lines case!
              True -> #(result, None)
              False -> #(result, Some(to_line - 1))
            }
          }

          Error(Nil) -> #(string.append(result, line), None)
        }
      }

      skip_until -> #(result, skip_until)
    }
  }

  result
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
) -> #(List(FileReplacements), List(ContentError)) {
  let #(code_files, errors) = load_code_files(config, inputs)
  let splitter = splitter.new(["\n", "\r\n"])
  let inputs = ReplaceInputs(splitter, inputs, code_files)

  let results = {
    use results, filename, expectations <- dict.fold(config, list.new())
    [get_file_replacements(inputs, filename, expectations), ..results]
  }

  // The errors here are missing inputs, so they are ignored
  let #(results, _) = result.partition(results)

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

/// Loads snippet sources. Ignores missing inputs.
fn load_code_files(
  config: Config,
  inputs: Dict(String, String),
) -> #(Dict(String, code_extractor.File), List(ContentError)) {
  use #(code_files, errors), filename <- set.fold(snippet_files(config), #(
    dict.new(),
    list.new(),
  ))

  case dict.get(inputs, filename) {
    Error(Nil) -> #(code_files, errors)
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
// If the file is not in the inputs, returns an error.
fn get_file_replacements(
  inputs: ReplaceInputs,
  filename: String,
  expectations: List(Expectation),
) -> Result(#(FileReplacements, List(ContentError)), Nil) {
  use content <- result.try(
    dict.get(inputs.input_files, filename)
    |> result.replace_error(Nil),
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

  let errors = option.values(errors)
  Ok(#(FileReplacements(filename, lines, replacements), errors))
}

fn create_replacement(
  inputs: ReplaceInputs,
  filename: String,
  sections: List(parser.Section),
  expectation: Expectation,
) -> Result(Replacement, Option(ContentError)) {
  use new_lines <- result.try(case expectation {
    config.ContentsOfFile(filename:, ..) ->
      dict.get(inputs.input_files, filename)
      // Missing inputs are not reported ere
      |> result.replace_error(None)
      |> result.map(lines.to_lines(inputs.splitter, _, []))

    config.CodeSegment(filename:, segment:, ..) ->
      dict.get(inputs.code_files, filename)
      // This was either a missing input or parsing failed,
      // we don't know at this point.
      |> result.replace_error(None)
      |> result.try(fn(code_file) {
        code_extractor.extract(code_file, segment)
        |> result.map_error(fn(e) {
          Some(case e {
            code_extractor.NameNotFound(..) -> CouldNotFindSnippet
            code_extractor.SpanExtractionFailed(..) -> CouldNotLoadSnippet
          }(filename, segment.name))
        })
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
    [parser.FencedCode(line_number:, lines:, prefix:, start_fence:, ..)] -> {
      let line_count = list.length(lines)
      let prefix = prefix <> string.repeat(" ", start_fence.indent)
      let new_lines = list.map(new_lines, string.append(prefix, _))
      Ok(Replacement(line_number, line_number + line_count, new_lines))
    }

    [] -> Error(Some(TagNotFound(filename, expectation.tag)))

    sections -> {
      let lines = list.map(sections, fn(section) { section.line_number })
      Error(Some(MultipleTagsFound(filename, expectation.tag, lines)))
    }
  }
}
