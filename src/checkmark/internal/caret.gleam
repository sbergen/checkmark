import gleam/bool
import iv.{type Array}
import splitter.{type Splitter}

pub type LineEnding {
  Lf
  CrLf
}

pub opaque type Document {
  Document(lines: Array(String), line_ending: LineEnding)
}

pub fn document_from_string(content: String) -> Document {
  // Handling this here makes the line splitting prettier
  use <- bool.guard(content == "", Document(iv.new(), Lf))

  let splitter = splitter.new(["\n", "\r\n"])
  let #(lines, #(lf_count, crlf_count)) =
    get_lines(splitter, content, [], #(0, 0))

  let line_ending = case crlf_count > lf_count {
    True -> CrLf
    False -> Lf
  }

  Document(lines:, line_ending:)
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

pub fn line_count(document: Document) -> Int {
  iv.length(document.lines)
}

pub fn get_line(document: Document, index: Int) -> Result(String, Nil) {
  iv.get(document.lines, index)
}

pub fn line_ending(document: Document) -> LineEnding {
  document.line_ending
}
