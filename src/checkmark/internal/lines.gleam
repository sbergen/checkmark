import gleam/list
import splitter

// TODO: Use caret instead of lines
pub fn to_lines(
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
