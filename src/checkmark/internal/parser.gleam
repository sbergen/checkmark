import checkmark/internal/caret.{type Text}
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/string

pub type CodeBlock {
  CodeBlock(
    line_number: Int,
    text: Text,
    prefix: String,
    start_fence: Fence,
    end_fence: Option(Fence),
  )
}

pub type Fence {
  Fence(fence: String, tag: String, indent: Int)
}

type Builder {
  Builder(line_number: Int, prefix: String, start_fence: Fence)
}

pub fn parse(text: Text, search_in_comments: Bool) -> List(CodeBlock) {
  let #(blocks, current_builder) = {
    use #(blocks, current_builder), line, line_number <- caret.fold_lines_with_index(
      text,
      #([], None),
    )

    let #(prefix, line, is_comment) = case search_in_comments {
      True -> parse_comment(line)
      False -> #("", line, False)
    }

    // Check special cases for comments
    case search_in_comments && !is_comment {
      // Line should NOT be included in code blocks, as it is not a comment
      True ->
        case current_builder {
          Some(builder) -> {
            let block = to_block(text, builder, line_number, None)
            #([block, ..blocks], None)
          }
          None -> #(blocks, None)
        }

      // Otherwise follow normal parsing
      False ->
        case parse_fence(line) {
          // No fence, keep scanning for current block end
          None -> #(blocks, current_builder)

          // Found fence:
          Some(new_fence) -> {
            case current_builder {
              // No current builder, start new, starting on next line:
              None -> #(
                blocks,
                Some(Builder(line_number + 1, prefix, new_fence)),
              )

              // Fenced code, check if it should be closed or not:
              Some(Builder(start_fence:, ..) as builder) ->
                case should_close(start_fence, new_fence) {
                  True -> {
                    let block =
                      to_block(text, builder, line_number, Some(new_fence))
                    #([block, ..blocks], None)
                  }

                  False -> #(blocks, current_builder)
                }
            }
          }
        }
    }
  }

  list.reverse(case current_builder {
    None -> blocks
    Some(builder) -> {
      let block = to_block(text, builder, caret.line_count(text), None)
      [block, ..blocks]
    }
  })
}

fn to_block(
  full_text: Text,
  builder: Builder,
  next_line_number: Int,
  end_fence: Option(Fence),
) {
  let Builder(line_number:, start_fence:, prefix:) = builder
  let line_count = next_line_number - line_number
  // TODO: is this assert ok?
  let assert Ok(text) = caret.slice_lines(full_text, line_number, line_count)
  let text = caret.map_lines(text, string.drop_start(_, string.length(prefix)))
  CodeBlock(
    line_number,
    caret.map_lines(text, remove_indent_up_to(_, start_fence.indent)),
    prefix:,
    start_fence:,
    end_fence:,
  )
}

fn remove_indent_up_to(string: String, indent: Int) -> String {
  case indent, string {
    0, _ -> string
    _, " " <> rest -> remove_indent_up_to(rest, indent - 1)
    _, _ -> string
  }
}

fn should_close(start: Fence, end: Fence) {
  string.starts_with(end.fence, start.fence)
}

/// Checks for a doc or module comment, and splits it into a prefix if found.
fn parse_comment(line: String) -> #(String, String, Bool) {
  case line {
    "/// " <> rest -> #("/// ", rest, True)
    "//// " <> rest -> #("//// ", rest, True)
    _ -> #("", line, False)
  }
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
