import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/string

pub type Section {
  Other(line_number: Int, lines: List(String))
  FencedCode(
    line_number: Int,
    lines: List(String),
    prefix: String,
    start_fence: Fence,
    end_fence: Option(Fence),
  )
}

pub type Fence {
  Fence(fence: String, info: String, indent: Int)
}

type SectionBuilder {
  OtherBuilder(line_number: Int, lines: List(String))
  FencedCodeBuilder(
    line_number: Int,
    lines: List(String),
    prefix: String,
    start_fence: Fence,
  )
}

type LineContent {
  LineContent(prefix: String, content: String)
}

fn to_string_with_prefix(line: LineContent) -> String {
  line.prefix <> line.content
}

pub fn parse(lines: List(String), search_in_comments: Bool) -> List(Section) {
  case lines {
    [first, ..rest] -> parse_lines(search_in_comments, 1, [], None, first, rest)
    [] -> []
  }
}

fn add_parts(builder: SectionBuilder, line: LineContent) {
  case builder {
    FencedCodeBuilder(..) ->
      FencedCodeBuilder(..builder, lines: [line.content, ..builder.lines])
    OtherBuilder(..) ->
      OtherBuilder(..builder, lines: [
        to_string_with_prefix(line),
        ..builder.lines
      ])
  }
}

fn to_section(builder: SectionBuilder, end_fence: Option(Fence)) {
  case builder {
    FencedCodeBuilder(line_number:, lines:, start_fence:, prefix:) ->
      FencedCode(
        line_number,
        strip_indent(lines, start_fence.indent) |> list.reverse(),
        prefix:,
        start_fence:,
        end_fence:,
      )

    OtherBuilder(line_number:, lines:) ->
      Other(line_number, list.reverse(lines))
  }
}

fn parse_lines(
  search_in_comments: Bool,
  line_number: Int,
  sections: List(Section),
  current_builder: Option(SectionBuilder),
  line: String,
  rest: List(String),
) -> List(Section) {
  let #(prefix, line, is_comment) = case search_in_comments {
    True -> parse_comment(line)
    False -> #("", line, False)
  }
  let line = LineContent(prefix, line)

  // Check special cases for comments
  let #(sections, current_section) = case search_in_comments && !is_comment {
    // Line should NOT be included in code blocks, as it is not a comment
    True ->
      case current_builder {
        None -> #(
          sections,
          Some(OtherBuilder(line_number, [to_string_with_prefix(line)])),
        )
        Some(builder) ->
          case builder {
            // End code block if comment ends
            FencedCodeBuilder(..) -> #(
              [to_section(builder, None), ..sections],
              Some(OtherBuilder(line_number, [to_string_with_prefix(line)])),
            )

            // Otherwise add to current
            OtherBuilder(..) -> #(sections, Some(add_parts(builder, line)))
          }
      }

    // Otherwise follow normal parsing
    False ->
      case parse_fence(line) {
        // No fence, add to current, or start new builder:
        None -> {
          let current_section = case current_builder {
            None -> OtherBuilder(line_number, [to_string_with_prefix(line)])
            Some(builder) -> add_parts(builder, line)
          }
          #(sections, Some(current_section))
        }

        // Found fence:
        Some(current_fence) -> {
          case current_builder {
            // No current builder, start new fenced code:
            None -> #(
              sections,
              Some(FencedCodeBuilder(
                line_number,
                [],
                line.prefix,
                current_fence,
              )),
            )

            // Other content: finalize it, start new fenced code
            Some(OtherBuilder(..) as other_builder) -> #(
              [to_section(other_builder, None), ..sections],
              Some(FencedCodeBuilder(
                line_number,
                [],
                line.prefix,
                current_fence,
              )),
            )

            // Fenced code, check if it should be closed or not:
            Some(FencedCodeBuilder(start_fence:, ..) as fence_builder) ->
              case should_close(start_fence, current_fence) {
                True -> #(
                  [to_section(fence_builder, Some(current_fence)), ..sections],
                  None,
                )

                False -> #(sections, Some(add_parts(fence_builder, line)))
              }
          }
        }
      }
  }

  case rest {
    // Nothing left, finalize the current builder, if any:
    [] -> {
      let sections = case current_section {
        None -> sections
        Some(builder) -> [to_section(builder, None), ..sections]
      }
      list.reverse(sections)
    }

    // More to parse, recurse on next line:
    [next_line, ..rest] -> {
      parse_lines(
        search_in_comments,
        line_number + 1,
        sections,
        current_section,
        next_line,
        rest,
      )
    }
  }
}

fn should_close(start: Fence, end: Fence) {
  string.starts_with(end.fence, start.fence)
}

fn strip_indent(lines: List(String), indent: Int) -> List(String) {
  lines
  |> list.map(remove_indent_up_to(_, indent))
}

fn remove_indent_up_to(string: String, indent: Int) -> String {
  case indent, string {
    0, _ -> string
    _, " " <> rest -> remove_indent_up_to(rest, indent - 1)
    _, _ -> string
  }
}

/// Checks for a doc or module comment, and splits it into a prefix if found.
fn parse_comment(line: String) -> #(String, String, Bool) {
  case line {
    "/// " <> rest -> #("/// ", rest, True)
    "//// " <> rest -> #("//// ", rest, True)
    _ -> #("", line, False)
  }
}

fn parse_fence(line: LineContent) -> Option(Fence) {
  // A code fence is a sequence of at least three consecutive backtick
  // characters (`) or tildes (~). (Tildes and backticks cannot be mixed.) 
  // A fenced code block begins with a code fence, 
  // preceded by up to three spaces of indentation.
  case line.content {
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

/// Figures out how many characters are in the fence, and builds a fence
fn build_fence(
  character: String,
  indent: Int,
  delimiters: Int,
  rest: String,
) -> Fence {
  case string.pop_grapheme(rest) {
    Ok(#(first, rest)) if first == character ->
      build_fence(character, indent, delimiters + 1, rest)

    _ -> {
      let fence = string.repeat(character, delimiters)
      Fence(fence:, info: rest, indent:)
    }
  }
}
