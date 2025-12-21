import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/string

pub type CodeBlock {
  ClodBlock(
    line_number: Int,
    lines: List(String),
    prefix: String,
    start_fence: Fence,
    end_fence: Option(Fence),
  )
}

pub type Fence {
  Fence(fence: String, tag: String, indent: Int)
}

type Builder {
  Builder(
    line_number: Int,
    lines: List(String),
    prefix: String,
    start_fence: Fence,
  )
}

type LineContent {
  LineContent(prefix: String, content: String)
}

pub fn parse(lines: List(String), search_in_comments: Bool) -> List(CodeBlock) {
  case lines {
    [first, ..rest] -> parse_lines(search_in_comments, 1, [], None, first, rest)
    [] -> []
  }
}

fn add_parts(builder: Builder, line: LineContent) -> Builder {
  Builder(..builder, lines: [line.content, ..builder.lines])
}

fn to_section(builder: Builder, end_fence: Option(Fence)) {
  let Builder(line_number:, lines:, start_fence:, prefix:) = builder
  ClodBlock(
    line_number,
    strip_indent(lines, start_fence.indent) |> list.reverse(),
    prefix:,
    start_fence:,
    end_fence:,
  )
}

fn parse_lines(
  search_in_comments: Bool,
  line_number: Int,
  sections: List(CodeBlock),
  current_builder: Option(Builder),
  line: String,
  rest: List(String),
) -> List(CodeBlock) {
  let #(prefix, line, is_comment) = case search_in_comments {
    True -> parse_comment(line)
    False -> #("", line, False)
  }
  let line = LineContent(prefix, line)

  // Check special cases for comments
  let #(sections, current_builder) = case search_in_comments && !is_comment {
    // Line should NOT be included in code blocks, as it is not a comment
    True ->
      case current_builder {
        Some(builder) -> #([to_section(builder, None), ..sections], None)
        None -> #(sections, None)
      }

    // Otherwise follow normal parsing
    False ->
      case parse_fence(line) {
        // No fence, add to current if building:
        None -> #(sections, option.map(current_builder, add_parts(_, line)))

        // Found fence:
        Some(new_fence) -> {
          case current_builder {
            // No current builder, start new:
            None -> #(
              sections,
              Some(Builder(line_number, [], line.prefix, new_fence)),
            )

            // Fenced code, check if it should be closed or not:
            Some(Builder(start_fence:, ..) as builder) ->
              case should_close(start_fence, new_fence) {
                True -> #(
                  [to_section(builder, Some(new_fence)), ..sections],
                  None,
                )

                False -> #(sections, Some(add_parts(builder, line)))
              }
          }
        }
      }
  }

  case rest {
    // Nothing left, finalize the current builder, if any:
    [] -> {
      let sections = case current_builder {
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
        current_builder,
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
      let tag = rest |> string.trim |> strip_frist_word(False)
      Fence(fence:, tag:, indent:)
    }
  }
}

/// Strips the first word and whitespace from a string
fn strip_frist_word(text: String, found_whitespace: Bool) -> String {
  case text, found_whitespace {
    "", _ -> text
    " " <> rest, _ -> strip_frist_word(rest, True)
    "\t" <> rest, _ -> strip_frist_word(rest, True)
    _, True -> text
    _, False -> {
      let assert Ok(#(_, rest)) = string.pop_grapheme(text)
      strip_frist_word(rest, False)
    }
  }
}
