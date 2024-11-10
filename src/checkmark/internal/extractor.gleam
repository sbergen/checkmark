import gleam/list
import kirala/markdown/parser

pub fn extract_gleam_code(
  markdown: String,
  filter: fn(String) -> Bool,
) -> List(String) {
  let tokens = parser.parse_all(markdown)
  use token <- list.filter_map(tokens)
  case token {
    parser.CodeBlock("gleam", _, code) -> {
      case filter(code) {
        True -> Ok(code)
        _ -> Error(Nil)
      }
    }
    _ -> Error(Nil)
  }
}
