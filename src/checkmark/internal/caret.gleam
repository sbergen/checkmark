import gleam/bool
import gleam/int
import gleam/result
import iv.{type Array}
import splitter.{type Splitter}

/// The default (gleamy) tab stop used, if not overridden
pub const default_tab_stop = 2

pub type LineEnding {
  Lf
  CrLf
}

pub opaque type Text {
  Text(lines: Array(String), line_ending: LineEnding, tab_stop: Int)
}

pub fn from_string(content: String) -> Text {
  // Handling this here makes the line splitting prettier
  use <- bool.guard(content == "", Text(iv.new(), Lf, default_tab_stop))

  let splitter = splitter.new(["\n", "\r\n"])
  let #(lines, #(lf_count, crlf_count)) =
    get_lines(splitter, content, [], #(0, 0))

  let line_ending = case crlf_count > lf_count {
    True -> CrLf
    False -> Lf
  }

  Text(lines:, line_ending:, tab_stop: default_tab_stop)
}

fn get_lines(
  splitter: Splitter,
  content: String,
  lines: List(String),
  ending_counts: #(Int, Int),
) -> #(Array(String), #(Int, Int)) {
  let #(line, ending, rest) = splitter.split(splitter, content)

  // Accumulate the current line
  let lines = [line, ..lines]
  let ending_counts = case ending {
    "\r\n" -> #(ending_counts.0, ending_counts.1 + 1)
    _ -> #(ending_counts.0 + 1, ending_counts.1)
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

pub fn to_string(text: Text) -> String {
  let line_ending = line_ending_string(text.line_ending)

  // TODO: See if this needs optimization
  use result, line, i <- iv.index_fold(text.lines, "")
  case i {
    0 -> result <> line
    _ -> result <> line_ending <> line
  }
}

/// Record updates can't be used with function captures,
/// so we make a function for this.
fn with_lines(text: Text, lines: Array(String)) {
  Text(..text, lines:)
}

/// Returns a new text with the given tab stop setting.
/// Only affects unindentation operations.
pub fn with_tab_stop_width(text: Text, tab_stop: Int) {
  Text(..text, tab_stop:)
}

/// Returns the number lines in the text.
pub fn line_count(text: Text) -> Int {
  iv.length(text.lines)
}

/// Returns a single line from the text, or an error if out of range.
/// Note that lines are 0-indexed.
pub fn line(text: Text, index: Int) -> Result(String, Nil) {
  iv.get(text.lines, index)
}

/// Returns the line ending used in the text.
pub fn line_ending(text: Text) -> LineEnding {
  text.line_ending
}

pub fn slice_lines(text: Text, from: Int, count: Int) -> Result(Text, Nil) {
  iv.slice(text.lines, from, count)
  |> result.map(with_lines(text, _))
}

fn line_ending_string(ending: LineEnding) -> String {
  case ending {
    Lf -> "\n"
    CrLf -> "\r\n"
  }
}

/// Replaces the lines
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
