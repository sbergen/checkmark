import checkmark/internal/parser.{Fence, FencedCode, Other}
import gleam/option.{None, Some}

fn comment_agnostic(body: fn(Bool) -> Nil) -> Nil {
  body(False)
  body(True)
}

pub fn empty_string_test() {
  use in_comments <- comment_agnostic()
  assert parser.parse([], in_comments) == []
}

pub fn no_snippets_test() {
  use in_comments <- comment_agnostic()

  let text = [
    "one\n",
    "two\r\n",
    "three\n",
  ]
  assert parser.parse(text, in_comments) == [parser.Other(1, text)]
}

pub fn basic_snippet_test() {
  assert parser.parse(
      [
        "start\n",
        "```gleam\n",
        "code\r\n",
        "more_code\n",
        "``` \n",
        "rest\n",
      ],
      False,
    )
    == [
      Other(1, ["start\n"]),
      FencedCode(
        2,
        "",
        [
          "code\r\n",
          "more_code\n",
        ],
        Fence("```", "gleam\n", 0),
        Some(Fence("```", " \n", 0)),
      ),
      Other(6, ["rest\n"]),
    ]
}

pub fn doc_comment_test() {
  assert parser.parse(
      [
        "pub const answer = 42\n",
        "\n",
        "/// start\n",
        "/// ```gleam\n",
        "/// code\r\n",
        "/// more_code\n",
        "/// ``` \n",
        "pub const answer_str = \"*\"\n",
      ],
      True,
    )
    == [
      Other(1, [
        "pub const answer = 42\n",
        "\n",
        "/// start\n",
      ]),
      FencedCode(
        4,
        "/// ",
        [
          "code\r\n",
          "more_code\n",
        ],
        Fence("```", "gleam\n", 0),
        Some(Fence("```", " \n", 0)),
      ),
      Other(8, ["pub const answer_str = \"*\"\n"]),
    ]
}

pub fn module_comment_test() {
  assert parser.parse(
      [
        "//// start\n",
        "//// ```gleam\n",
        "//// code\n",
        "//// ``` \n",
        "//// rest\n",
      ],
      True,
    )
    == [
      Other(1, [
        "//// start\n",
      ]),
      FencedCode(
        2,
        "//// ",
        [
          "code\n",
        ],
        Fence("```", "gleam\n", 0),
        Some(Fence("```", " \n", 0)),
      ),
      Other(5, ["//// rest\n"]),
    ]
}

pub fn unfinished_comment_block_test() {
  assert parser.parse(
      [
        "//// start\n",
        "//// ```gleam\n",
        "//// code\n",
        "rest\n",
      ],
      True,
    )
    == [
      Other(1, [
        "//// start\n",
      ]),
      FencedCode(
        2,
        "//// ",
        [
          "code\n",
        ],
        Fence("```", "gleam\n", 0),
        None,
      ),
      Other(4, ["rest\n"]),
    ]
}

pub fn indented_snippet_test() {
  assert parser.parse(
      [
        "   ```gleam\n",
        "   code\n",
        "     more_code\n",
        " not indented enough\n",
        "  ```\n",
      ],
      False,
    )
    == [
      FencedCode(
        1,
        "",
        [
          "code\n",
          "  more_code\n",
          "not indented enough\n",
        ],
        Fence("```", "gleam\n", 3),
        Some(Fence("```", "\n", 2)),
      ),
    ]
}

pub fn non_matching_fences_test() {
  assert parser.parse(
      [
        "````\n",
        "```\n",
        "~~~\n",
        "code\n",
        "````\n",
      ],
      False,
    )
    == [
      FencedCode(
        1,
        "",
        [
          "```\n",
          "~~~\n",
          "code\n",
        ],
        Fence("````", "\n", 0),
        Some(Fence("````", "\n", 0)),
      ),
    ]
}

pub fn missing_end_fence_test() {
  assert parser.parse(
      [
        "```\n",
        "code\n",
      ],
      False,
    )
    == [FencedCode(1, "", ["code\n"], Fence("```", "\n", 0), None)]
}

pub fn empty_fence_test() {
  assert parser.parse(["```info\n"], False)
    == [FencedCode(1, "", [], Fence("```", "info\n", 0), None)]
}

pub fn emtpy_line_preservation_test() {
  assert parser.parse(
      [
        "\n",
        "text\n",
        "\n",
        "```\n",
        "\n",
        "code\n",
        "\n",
        "```\n",
        "\n",
        "\n",
      ],
      False,
    )
    == [
      Other(1, [
        "\n",
        "text\n",
        "\n",
      ]),
      FencedCode(
        4,
        "",
        [
          "\n",
          "code\n",
          "\n",
        ],
        Fence("```", "\n", 0),
        Some(Fence("```", "\n", 0)),
      ),
      Other(9, [
        "\n",
        "\n",
      ]),
    ]
}
