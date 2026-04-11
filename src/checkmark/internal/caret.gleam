//// Caret provides utilities for efficient line-oriented editing of text.
//// Caret detects the most prevalent line ending,
//// and forces line ending normalization when converting text back to a string.
//// Thus it does not preserve mixed line-endings,
//// which might make it unsuitable for certain use cases.
//// However, caret does support custom line endings,
//// in case the typical \n or \r\n endings are not used.

// Implementation notes:
// As of 2026-04, splitter and string operations are so efficient,
// that providing operations to construct from a list of strings,
// keeping the guarantee of no line breaks within a line,
// is less efficient than just building the string and then splitting it.
// This applies at least at the magnitude of 100k lines with hundreds of characters.

import gleam/bool
import gleam/dict.{type Dict}
import gleam/int
import gleam/option
import gleam/result
import iv.{type Array}
import splitter.{type Splitter}

/// The default (gleamy) tab stop used, if not overridden
pub const default_tab_stop = 2

/// A line-based representation of text.
/// In addition to the lines (without line endings),
/// contains information about the line ending to use when rendering to a `String`
/// and a tab-stop setting.
pub opaque type Text {
  Text(lines: Array(String), line_ending: String, tab_stop: Int)
}

/// Constructs an empty text with the default settings (\n, tab stop of 2).
/// Note that an empty `Text` can not be constructed using `from_string`,
/// as that will include at least one line.
pub fn new() -> Text {
  Text(iv.new(), "\n", default_tab_stop)
}

/// Constructs a `Text` from a string,
/// by splitting it into lines using default line endings (\n, \r\n).
/// The most prevalent line ending is automatically detected,
/// the result from ties being undefined.
/// \n is used if no line endings are found.
pub fn from_string(content: String) -> Text {
  from_string_with_line_endings(content, ["\n", "\r\n"], "\n")
}

/// Constructs a `Text` from a string,
/// by splitting it into lines using a custom set of line endings.
/// The most prevalent line ending is automatically detected,
/// the result from ties being undefined.
/// If no line endings are encountered, the given default is used.
pub fn from_string_with_line_endings(
  content: String,
  line_endings: List(String),
  default_line_ending: String,
) -> Text {
  // Handling this here makes the line splitting prettier
  use <- bool.guard(
    content == "",
    Text(iv.wrap(""), default_line_ending, default_tab_stop),
  )

  let splitter = splitter.new(line_endings)
  let #(lines, line_endings) = get_lines(splitter, content, [], dict.new())

  let line_ending =
    dict.fold(line_endings, #(default_line_ending, 0), fn(max, ending, count) {
      case ending, count > max.1 {
        _, True -> #(ending, count)
        _, False -> max
      }
    }).0

  Text(lines:, line_ending:, tab_stop: default_tab_stop)
}

fn get_lines(
  splitter: Splitter,
  content: String,
  lines: List(String),
  ending_counts: Dict(String, Int),
) -> #(Array(String), Dict(String, Int)) {
  let #(line, ending, rest) = splitter.split(splitter, content)

  // Accumulate the current line
  let lines = [line, ..lines]
  let ending_counts = case ending {
    "" -> ending_counts
    _ ->
      dict.upsert(ending_counts, ending, fn(count) {
        option.unwrap(count, 0) + 1
      })
  }

  case rest {
    "" -> {
      // If the last line has a line-ending, add one empty line
      let lines = case ending {
        "" -> lines
        _ -> ["", ..lines]
      }
      #(iv.from_reverse_list(lines), ending_counts)
    }
    _ -> get_lines(splitter, rest, lines, ending_counts)
  }
}

/// Renders the text into a string by concatenating the lines,
/// separating them with the configured line ending.
/// No trailing newline is rendered, unless there is an empty line at the end.
pub fn to_string(text: Text) -> String {
  use result, line, i <- iv.index_fold(text.lines, "")
  case i {
    0 -> result <> line
    _ -> result <> text.line_ending <> line
  }
}

/// Record updates can't be used with function captures,
/// so we make a function for this.
fn with_lines(text: Text, lines: Array(String)) -> Text {
  Text(..text, lines:)
}

/// Returns a new text with the given tab stop setting.
/// Only affects unindentation operations.
pub fn with_tab_stop_width(text: Text, tab_stop: Int) -> Text {
  Text(..text, tab_stop:)
}

/// Returns a new text with the given line ending
pub fn with_line_ending(text: Text, ending: String) -> Text {
  Text(..text, line_ending: ending)
}

/// Checks whether two texts have the same line content.
/// Ignores line ending type and tab stop width.
/// Note that in general, structural equality on a `Text` instance
/// might not return the correct result, due to using `iv` under the hood.
pub fn lines_equal(a: Text, b: Text) -> Bool {
  iv.equal(a.lines, b.lines)
}

/// Returns the number of lines in the text.
/// Note that a trailing newline will result in one empty line at the end,
/// which is included in this count.
pub fn line_count(text: Text) -> Int {
  iv.size(text.lines)
}

/// Returns a single line from the text, or an error if out of range.
/// Note that lines are 0-indexed.
pub fn line(text: Text, index: Int) -> Result(String, Nil) {
  iv.get(text.lines, index)
}

/// Returns the line ending used in the text.
pub fn line_ending(text: Text) -> String {
  text.line_ending
}

/// Returns a new Text from a slice of lines,
/// or an error if the lines are out of range.
pub fn slice_lines(text: Text, from: Int, count: Int) -> Result(Text, Nil) {
  iv.slice(text.lines, from, count)
  |> result.map(with_lines(text, _))
}

/// Returns a new Text from a slice of lines,
/// clamping the given range if it is out of bounds.
pub fn slice_lines_clamped(text: Text, from: Int, count: Int) -> Text {
  iv.slice_clamped(text.lines, from, count)
  |> with_lines(text, _)
}

/// Replaces the number of lines at the given index with another text.
pub fn replace_lines(
  text: Text,
  at index: Int,
  replace count: Int,
  with replacement: Text,
) -> Result(Text, Nil) {
  iv.replace(text.lines, index, count, replacement.lines)
  |> result.map(with_lines(text, _))
}

/// Unindents the text based on the smallest indentation level found in
/// lines including characters that are not tabs or spaces.
/// If the minimum indentation is less than one tab stop,
/// then no unindentation is performed.
pub fn auto_unindent(text: Text) -> Text {
  let amount = {
    use amount, line <- iv.fold(text.lines, Error(Nil))
    let new_amount = count_indent(line, text.tab_stop, 0, 0)

    case amount, new_amount {
      _, Error(Nil) -> amount
      Error(Nil), Ok(new_amount) -> Ok(new_amount)
      Ok(old_amount), Ok(new_amount) -> Ok(int.min(old_amount, new_amount))
    }
  }

  case amount {
    Error(Nil) -> text
    Ok(amount) -> unindent(text, amount)
  }
}

/// Unindents every line the given number of tab stops, if possible.
pub fn unindent(text: Text, tab_stops: Int) -> Text {
  with_lines(
    text,
    iv.map(text.lines, unindent_line(_, text.tab_stop, tab_stops, 0)),
  )
}

// Counts the indent in whole tab stops
fn count_indent(
  string: String,
  tab_stop: Int,
  spaces: Int,
  tab_stops: Int,
) -> Result(Int, Nil) {
  case string {
    " " <> rest -> {
      let spaces = spaces + 1
      let #(spaces, tab_stops) = case spaces == tab_stop {
        True -> #(0, tab_stops + 1)
        False -> #(spaces, tab_stops)
      }
      count_indent(rest, tab_stop, spaces, tab_stops)
    }

    "\t" <> rest -> count_indent(rest, tab_stop, 0, tab_stops + 1)

    // No non-whitespace found
    "" -> Error(Nil)

    _ -> Ok(tab_stops)
  }
}

fn unindent_line(
  string: String,
  tab_stop: Int,
  tab_stops: Int,
  removed_spaces: Int,
) -> String {
  case tab_stops, string {
    0, _ -> string
    _, " " <> rest -> {
      let removed_spaces = removed_spaces + 1
      let #(removed_spaces, tab_stops) = case removed_spaces == tab_stop {
        True -> #(0, tab_stops - 1)
        False -> #(removed_spaces, tab_stops)
      }

      unindent_line(rest, tab_stop, tab_stops, removed_spaces)
    }

    _, "\t" <> rest -> unindent_line(rest, tab_stop, 0, tab_stops - 1)

    // Ran out of whitespace
    _, _ -> string
  }
}

/// Returns a new text with each line replaced by zero or more lines.
/// Keeps the tab stop and line ending of the first argument.
/// Note that a `map_lines` function does not exist,
/// because we need to guarantee no lines contain any newline characters.
pub fn flat_map_lines(text: Text, with: fn(String) -> Text) -> Text {
  with_lines(text, iv.flat_map(text.lines, fn(line) { with(line).lines }))
}

pub fn transform_line_range(
  text: Text,
  at index: Int,
  count count: Int,
  with fun: fn(Text) -> Text,
) -> Result(Text, Nil) {
  slice_lines(text, index, count)
  |> result.map(fun)
  |> result.try(replace_lines(text, index, count, _))
}

/// Removes a single trailing newline, if present
pub fn without_trailing_newline(text: Text) -> Text {
  case iv.at(text.lines, -1) {
    Ok(last) if last == "" -> with_lines(text, iv.drop_last(text.lines, 1))
    _ -> text
  }
}

pub fn fold_lines(
  over text: Text,
  from state: state,
  with fun: fn(state, String) -> state,
) -> state {
  iv.fold(text.lines, state, fun)
}

pub fn fold_lines_with_index(
  over text: Text,
  from state: state,
  with fun: fn(state, String, Int) -> state,
) -> state {
  iv.index_fold(text.lines, state, fun)
}

pub fn fold_lines_right(
  over text: Text,
  from state: state,
  with fun: fn(state, String) -> state,
) -> state {
  iv.fold_right(text.lines, state, fun)
}

pub fn fold_lines_with_index_right(
  over text: Text,
  from state: state,
  with fun: fn(state, String, Int) -> state,
) -> state {
  iv.index_fold_right(text.lines, state, fun)
}
