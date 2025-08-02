import checkmark/internal/parser.{Fence, FencedCode, Other}
import gleam/option.{None, Some}

pub fn empty_string_test() {
  assert parser.parse("") == []
}

pub fn no_snippets_test() {
  let text = "one\ntwo\r\nthree"
  assert parser.parse(text) == [parser.Other(1, text)]
}

pub fn basic_snippet_test() {
  assert parser.parse("start\n```gleam\ncode\r\nmore_code\n``` \nrest")
    == [
      Other(1, "start\n"),
      FencedCode(
        2,
        "code\r\nmore_code\n",
        Fence("```", "gleam\n", 0),
        Some(Fence("```", " \n", 0)),
      ),
      Other(6, "rest"),
    ]
}

pub fn indented_snippet_test() {
  assert parser.parse(
      "   ```gleam\n   code\n     more_code\n not indented enough\n  ```",
    )
    == [
      FencedCode(
        1,
        "code\n  more_code\nnot indented enough\n",
        Fence("```", "gleam\n", 3),
        Some(Fence("```", "", 2)),
      ),
    ]
}

pub fn non_matching_fences_test() {
  assert parser.parse("````\n```\n~~~\ncode\n````")
    == [
      FencedCode(
        1,
        "```\n~~~\ncode\n",
        Fence("````", "\n", 0),
        Some(Fence("````", "", 0)),
      ),
    ]
}

pub fn missing_end_fence_test() {
  assert parser.parse("```\ncode")
    == [FencedCode(1, "code", Fence("```", "\n", 0), None)]
}

pub fn empty_fence_test() {
  assert parser.parse("```info")
    == [FencedCode(1, "", Fence("```", "info", 0), None)]
}

pub fn emtpy_line_preservation_test() {
  assert parser.parse("\ntext\n\n```\n\ncode\n\n```\n\n\n")
    == [
      Other(1, "\ntext\n\n"),
      FencedCode(
        4,
        "\ncode\n\n",
        Fence("```", "\n", 0),
        Some(Fence("```", "\n", 0)),
      ),
      Other(9, "\n\n"),
    ]
}
