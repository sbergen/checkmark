import checkmark/internal/parser.{Fence, FencedCode, Other}
import gleam/option.{None, Some}
import gleam/string

fn lines(lines: List(String)) -> String {
  lines |> string.join("\n")
}

fn comment_agnostic(body: fn(Bool) -> Nil) -> Nil {
  body(False)
  body(True)
}

pub fn empty_string_test() {
  use in_comments <- comment_agnostic()
  assert parser.parse("", in_comments) == []
}

pub fn no_snippets_test() {
  use in_comments <- comment_agnostic()

  let text =
    lines([
      "one",
      "two\r",
      "three",
    ])
  assert parser.parse(text, in_comments) == [parser.Other(1, text)]
}

pub fn basic_snippet_test() {
  assert parser.parse(
      lines([
        "start",
        "```gleam",
        "code\r",
        "more_code",
        "``` ",
        "rest",
      ]),
      False,
    )
    == [
      Other(1, "start\n"),
      FencedCode(
        2,
        lines([
          "code\r",
          "more_code",
          "",
        ]),
        Fence("```", "gleam\n", 0),
        Some(Fence("```", " \n", 0)),
      ),
      Other(6, "rest"),
    ]
}

pub fn indented_snippet_test() {
  assert parser.parse(
      lines([
        "   ```gleam",
        "   code",
        "     more_code",
        " not indented enough",
        "  ```",
      ]),
      False,
    )
    == [
      FencedCode(
        1,
        lines([
          "code",
          "  more_code",
          "not indented enough",
          "",
        ]),
        Fence("```", "gleam\n", 3),
        Some(Fence("```", "", 2)),
      ),
    ]
}

pub fn non_matching_fences_test() {
  assert parser.parse(
      lines([
        "````",
        "```",
        "~~~",
        "code",
        "````",
      ]),
      False,
    )
    == [
      FencedCode(
        1,
        lines([
          "```",
          "~~~",
          "code",
          "",
        ]),
        Fence("````", "\n", 0),
        Some(Fence("````", "", 0)),
      ),
    ]
}

pub fn missing_end_fence_test() {
  assert parser.parse(
      lines([
        "```",
        "code",
      ]),
      False,
    )
    == [FencedCode(1, "code", Fence("```", "\n", 0), None)]
}

pub fn empty_fence_test() {
  assert parser.parse("```info", False)
    == [FencedCode(1, "", Fence("```", "info", 0), None)]
}

pub fn emtpy_line_preservation_test() {
  assert parser.parse(
      lines([
        "",
        "text",
        "",
        "```",
        "",
        "code",
        "",
        "```",
        "",
        "",
        "",
      ]),
      False,
    )
    == [
      Other(
        1,
        lines([
          "",
          "text",
          "",
          "",
        ]),
      ),
      FencedCode(
        4,
        lines([
          "",
          "code",
          "",
          "",
        ]),
        Fence("```", "\n", 0),
        Some(Fence("```", "\n", 0)),
      ),
      Other(
        9,
        lines([
          "",
          "",
          "",
        ]),
      ),
    ]
}
