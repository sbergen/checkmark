//// TODO: docs

import checkmark/internal/code_extractor.{type CodeSegment, type ExtractError}
import checkmark/internal/config.{type Config, type Expectation}
import checkmark/internal/lines
import checkmark/internal/parser
import gleam/dict.{type Dict}
import gleam/list
import gleam/result
import gleam/set.{type Set}
import gleam/string
import splitter

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

pub type ReplaceError {
  InputNotProvided(filename: String)
  CouldNotParseSnippetSource(file: String)
  SnippetNotFound(file: String, name: String)
  CouldNotLoadSnippet(file: String, name: String)
  TargetMissing(file: String, tag: String)
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
) -> #(List(FileReplacements), List(ReplaceError)) {
  let state =
    new_state(inputs)
    |> load_snippets(config)

  let state = {
    use state, filename, expectations <- dict.fold(config, state)
    get_file_replacements(state, filename, expectations)
  }

  let errors = list.new()
  let errors = {
    use errors, missing_input <- set.fold(state.missing_inputs, errors)
    [InputNotProvided(missing_input), ..errors]
  }
  let errors = {
    use errors, invalid_file <- set.fold(state.invalid_code, errors)
    [CouldNotParseSnippetSource(invalid_file), ..errors]
  }
  let errors = {
    use errors, invalid_segment <- set.fold(state.invalid_segments, errors)
    let error = case invalid_segment.error {
      code_extractor.NameNotFound(name:) ->
        SnippetNotFound(invalid_segment.filename, name)

      code_extractor.SpanExtractionFailed(name:) ->
        CouldNotLoadSnippet(invalid_segment.filename, name)
    }
    [error, ..errors]
  }
  let errors = {
    use errors, missing_target <- set.fold(state.missing_targets, errors)
    [TargetMissing(missing_target.filename, missing_target.tag), ..errors]
  }

  #(state.replacements, errors)
}

type InvalidSegment {
  InvalidSegment(filename: String, error: ExtractError)
}

type MissingTargetBlock {
  MissingTargetBlock(filename: String, tag: String)
}

/// Helper record for incrementally building state
type ReplaceState {
  ReplaceState(
    splitter: splitter.Splitter,
    /// Contents of input files
    inputs: Dict(String, String),
    /// Parsed Gleam files (we parse them only once)
    code_files: Dict(String, code_extractor.File),
    /// Successful replacements
    replacements: List(FileReplacements),
    /// The input file contents was missing
    missing_inputs: Set(String),
    /// A code file could not be parsed as Gleam code
    invalid_code: Set(String),
    /// Code segments that could not be extracted from an otherwise valid file
    invalid_segments: Set(InvalidSegment),
    /// Missing code blocks in target
    missing_targets: Set(MissingTargetBlock),
  )
}

/// Missing
fn new_state(inputs: Dict(String, String)) -> ReplaceState {
  let splitter = splitter.new(["\n", "\r\n"])
  ReplaceState(
    splitter,
    inputs,
    dict.new(),
    list.new(),
    set.new(),
    set.new(),
    set.new(),
    set.new(),
  )
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
  ReplaceState(..state, missing_inputs: set.insert(state.missing_inputs, input))
}

fn add_missing_target(
  state: ReplaceState,
  filename: String,
  tag: String,
) -> ReplaceState {
  ReplaceState(
    ..state,
    missing_targets: set.insert(
      state.missing_targets,
      MissingTargetBlock(filename, tag),
    ),
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
  ReplaceState(..state, invalid_code: set.insert(state.invalid_code, input))
}

fn add_invalid_segment(
  state: ReplaceState,
  filename: String,
  error: ExtractError,
) -> ReplaceState {
  ReplaceState(
    ..state,
    invalid_segments: set.insert(
      state.invalid_segments,
      InvalidSegment(filename:, error:),
    ),
  )
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
        add_missing_target(state, filename, expectation.tag),
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
  use section <- result.try(
    list.find(sections, fn(section) {
      case section {
        parser.FencedCode(start_fence: fence, ..) ->
          string.trim(fence.info) == tag
        _ -> False
      }
    }),
  )

  let line_count = list.length(section.lines)
  Ok(Replacement(
    section.line_number,
    section.line_number + line_count,
    replacement,
  ))
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
