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

pub fn parse(content: String, in_comments: Bool) -> List(Section) {
  use <- bool.guard(when: content == "", return: [])

  let line_ends = splitter.new(["\n", "\r\n"])
  let #(line, ending, rest) = splitter.split(line_ends, content)
  parse_lines(line_ends, in_comments, 1, [], None, line, ending, rest)
}

fn add_parts(builder: SectionBuilder, line: String, ending: String) {
  let parts = [ending, line, ..builder.parts]
  case builder {
    FencedCodeBuilder(..) -> FencedCodeBuilder(..builder, parts:)
    OtherBuilder(..) -> OtherBuilder(..builder, parts:)
  }
}

fn to_section(builder: SectionBuilder, end_fence: Option(Fence)) {
  case builder {
    FencedCodeBuilder(start_line:, parts:, start_fence:) ->
      FencedCode(
        start_line,
        parts_to_string(parts, start_fence.indent),
        start_fence,
        end_fence,
      )

    OtherBuilder(start_line:, parts:) ->
      Other(start_line, parts_to_string(parts, 0))
  }
}

fn parse_lines(
  splitter: Splitter,
  in_comments: Bool,
  line_number: Int,
  sections: List(Section),
  current_builder: Option(SectionBuilder),
  line: String,
  ending: String,
  rest: String,
) -> List(Section) {
  let #(sections, current_section) = case parse_fence(line, ending) {
    // No fence, add to current, or start new builder:
    None -> {
      let current_section = case current_builder {
        None -> OtherBuilder(line_number, [ending, line])
        Some(builder) -> add_parts(builder, line, ending)
      }
      #(sections, Some(current_section))
    }

    // Found fence:
    Some(current_fence) -> {
      case current_builder {
        // No current builder, start new fenced code:
        None -> #(
          sections,
          Some(FencedCodeBuilder(line_number, [], current_fence)),
        )

        // Other content: finalize it, start new fenced code
        Some(OtherBuilder(..) as other_builder) -> #(
          [to_section(other_builder, None), ..sections],
          Some(FencedCodeBuilder(line_number, [], current_fence)),
        )

        // Fenced code, check if it should be closed or not:
        Some(FencedCodeBuilder(start_fence:, ..) as fence_builder) ->
          case should_close(start_fence, current_fence) {
            True -> #(
              [to_section(fence_builder, Some(current_fence)), ..sections],
              None,
            )

            False -> #(sections, Some(add_parts(fence_builder, line, ending)))
          }
      }
    }
  }

  case rest {
    // Nothing left, finalize the current builder, if any:
    "" -> {
      let sections = case current_section {
        None -> sections
        Some(builder) -> [to_section(builder, None), ..sections]
      }
      list.reverse(sections)
    }

    // More to parse, recurse on next line:
    rest -> {
      let #(content, ending, rest) = splitter.split(splitter, rest)
      parse_lines(
        splitter,
        in_comments,
        line_number + 1,
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

fn parts_to_string(parts: List(String), indent: Int) -> String {
  parts
  |> list.map(remove_indent_up_to(_, indent))
  |> list.reverse
  |> string.join("")
}

fn remove_indent_up_to(string: String, indent: Int) -> String {
  case indent, string {
    0, _ -> string
    _, " " <> rest -> remove_indent_up_to(rest, indent - 1)
    _, _ -> string
  }
}

fn parse_fence(line: String, ending: String) -> Option(Fence) {
  // A code fence is a sequence of at least three consecutive backtick
  // characters (`) or tildes (~). (Tildes and backticks cannot be mixed.) 
  // A fenced code block begins with a code fence, 
  // preceded by up to three spaces of indentation.
  case line {
    "```" <> rest -> Some(build_fence("`", 0, 3, rest, ending))
    " ```" <> rest -> Some(build_fence("`", 1, 3, rest, ending))
    "  ```" <> rest -> Some(build_fence("`", 2, 3, rest, ending))
    "   ```" <> rest -> Some(build_fence("`", 3, 3, rest, ending))
    "~~~" <> rest -> Some(build_fence("~", 0, 3, rest, ending))
    " ~~~" <> rest -> Some(build_fence("~", 1, 3, rest, ending))
    "  ~~~" <> rest -> Some(build_fence("~", 2, 3, rest, ending))
    "   ~~~" <> rest -> Some(build_fence("~", 3, 3, rest, ending))
    _ -> None
  }
}

fn build_fence(
  character: String,
  indent: Int,
  delimiters: Int,
  rest: String,
  ending: String,
) -> Fence {
  case string.pop_grapheme(rest) {
    Ok(#(first, rest)) if first == character ->
      build_fence(character, indent, delimiters + 1, rest, ending)
    _ -> Fence(string.repeat(character, delimiters), rest <> ending, indent)
  }
}
