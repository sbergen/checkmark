import gleam/bool
import gleam/result
import iv.{type Array}
import splitter.{type Splitter}

pub type LineEnding {
  Lf
  CrLf
}

pub opaque type Text {
  Text(lines: Array(String), line_ending: LineEnding)
}

pub fn from_string(content: String) -> Text {
  // Handling this here makes the line splitting prettier
  use <- bool.guard(content == "", Text(iv.new(), Lf))

  let splitter = splitter.new(["\n", "\r\n"])
  let #(lines, #(lf_count, crlf_count)) =
    get_lines(splitter, content, [], #(0, 0))

  let line_ending = case crlf_count > lf_count {
    True -> CrLf
    False -> Lf
  }

  Text(lines:, line_ending:)
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
  |> result.map(Text(_, text.line_ending))
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
  |> result.map(Text(_, text.line_ending))
}
