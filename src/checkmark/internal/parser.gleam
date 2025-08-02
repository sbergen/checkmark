import gleam/bool
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/string
import splitter.{type Splitter}

pub type Section {
  Other(start_line: Int, content: String)
  FencedCode(
    start_line: Int,
    content: String,
    start_fence: Fence,
    end_fence: Option(Fence),
  )
}

pub type Fence {
  Fence(fence: String, info: String, indent: Int)
}

type SectionBuilder {
  OtherBuilder(start_line: Int, parts: List(String))
  FencedCodeBuilder(start_line: Int, parts: List(String), start_fence: Fence)
}

pub fn parse(content: String) -> List(Section) {
  use <- bool.guard(when: content == "", return: [])

  let line_ends = splitter.new(["\n", "\r\n"])
  let #(line, ending, rest) = splitter.split(line_ends, content)
  parse_lines(line_ends, 1, [], None, line, ending, rest)
}

fn parse_lines(
  splitter: Splitter,
  line: Int,
  sections: List(Section),
  current_section: Option(SectionBuilder),
  content: String,
  ending: String,
  rest: String,
) {
  let #(sections, current_section) = case parse_fence(content) {
    None -> {
      let current_section = case current_section {
        None -> OtherBuilder(line, [ending, content])
        Some(builder) -> {
          let parts = [ending, content, ..builder.parts]
          case builder {
            FencedCodeBuilder(line, _, start_fence:) ->
              FencedCodeBuilder(line, parts, start_fence)
            OtherBuilder(line, _) -> OtherBuilder(line, parts)
          }
        }
      }
      #(sections, Some(current_section))
    }

    Some(fence) ->
      case current_section {
        None -> #(sections, Some(FencedCodeBuilder(line, [], fence)))
        Some(OtherBuilder(prev_line, parts)) -> #(
          [Other(prev_line, parts_to_string(parts)), ..sections],
          Some(FencedCodeBuilder(line, [], fence)),
        )
        Some(FencedCodeBuilder(start_line:, parts:, start_fence:)) ->
          case should_close(start_fence, fence) {
            True -> #(
              [
                FencedCode(
                  start_line,
                  parts_to_string(parts),
                  start_fence,
                  Some(fence),
                ),
                ..sections
              ],
              None,
            )
            False -> #(
              sections,
              Some(FencedCodeBuilder(
                start_line,
                [ending, content, ..parts],
                start_fence,
              )),
            )
          }
      }
  }

  case rest {
    "" -> {
      let sections = case current_section {
        None -> sections
        Some(builder) ->
          case builder {
            FencedCodeBuilder(start_line:, start_fence:, parts:) -> [
              FencedCode(start_line, parts_to_string(parts), start_fence, None),
              ..sections
            ]
            OtherBuilder(start_line:, parts:) -> [
              Other(start_line, parts_to_string(parts)),
              ..sections
            ]
          }
      }
      list.reverse(sections)
    }

    rest -> {
      let #(content, ending, rest) = splitter.split(splitter, rest)
      parse_lines(
        splitter,
        line + 1,
        sections,
        current_section,
        content,
        ending,
        rest,
      )
    }
  }
}

fn should_close(start: Fence, end: Fence) {
  string.starts_with(end.fence, start.fence)
}

fn parts_to_string(parts: List(String)) -> String {
  parts |> list.reverse |> string.join("")
}

fn parse_fence(line: String) -> Option(Fence) {
  // A code fence is a sequence of at least three consecutive backtick
  // characters (`) or tildes (~). (Tildes and backticks cannot be mixed.) 
  // A fenced code block begins with a code fence, 
  // preceded by up to three spaces of indentation.
  case line {
    "```" <> rest -> Some(build_fence("`", 0, 3, rest))
    " ```" <> rest -> Some(build_fence("`", 1, 3, rest))
    "  ```" <> rest -> Some(build_fence("`", 2, 3, rest))
    "   ```" <> rest -> Some(build_fence("`", 3, 3, rest))
    "~~~" <> rest -> Some(build_fence("~", 0, 3, rest))
    " ~~~" <> rest -> Some(build_fence("~", 1, 3, rest))
    "  ~~~" <> rest -> Some(build_fence("~", 2, 3, rest))
    "   ~~~" <> rest -> Some(build_fence("~", 3, 3, rest))
    _ -> None
  }
}

fn build_fence(
  character: String,
  indent: Int,
  delimiters: Int,
  rest: String,
) -> Fence {
  case string.pop_grapheme(rest) {
    Ok(#(first, rest)) if first == character ->
      build_fence(character, indent, delimiters + 1, rest)
    _ -> Fence(string.repeat(character, delimiters), rest, indent)
  }
}
