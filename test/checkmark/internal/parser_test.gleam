import checkmark/internal/parser.{ClodBlock, Fence}
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
  assert parser.parse(text, in_comments) == []
}

pub fn basic_snippet_test() {
  assert parser.parse(
      [
        "start\n",
        "```gleam tag \n",
        "code\r\n",
        "more_code\n",
        "``` \n",
        "rest\n",
      ],
      False,
    )
    == [
      ClodBlock(
        2,
        [
          "code\r\n",
          "more_code\n",
        ],
        "",
        Fence("```", "tag", 0),
        Some(Fence("```", "", 0)),
      ),
    ]
}

pub fn doc_comment_test() {
  assert parser.parse(
      [
        "pub const answer = 42\n",
        "\n",
        "/// start\n",
        "/// ```gleam   tag \n",
        "/// code\r\n",
        "/// more_code\n",
        "/// ``` \n",
        "pub const answer_str = \"*\"\n",
      ],
      True,
    )
    == [
      ClodBlock(
        4,
        [
          "code\r\n",
          "more_code\n",
        ],
        "/// ",
        Fence("```", "tag", 0),
        Some(Fence("```", "", 0)),
      ),
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
      ClodBlock(
        2,
        [
          "code\n",
        ],
        "//// ",
        Fence("```", "", 0),
        Some(Fence("```", "", 0)),
      ),
    ]
}

pub fn unfinished_comment_block_test() {
  assert parser.parse(
      [
        "//// start\n",
        "//// ```gleam tag\n",
        "//// code\n",
        "rest\n",
      ],
      True,
    )
    == [
      ClodBlock(
        2,
        [
          "code\n",
        ],
        "//// ",
        Fence("```", "tag", 0),
        None,
      ),
    ]
}

pub fn indented_snippet_test() {
  assert parser.parse(
      [
        "   ```gleam tag\n",
        "   code\n",
        "     more_code\n",
        " not indented enough\n",
        "  ```\n",
      ],
      False,
    )
    == [
      ClodBlock(
        1,
        [
          "code\n",
          "  more_code\n",
          "not indented enough\n",
        ],
        "",
        Fence("```", "tag", 3),
        Some(Fence("```", "", 2)),
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
      ClodBlock(
        1,
        [
          "```\n",
          "~~~\n",
          "code\n",
        ],
        "",
        Fence("````", "", 0),
        Some(Fence("````", "", 0)),
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
    == [ClodBlock(1, ["code\n"], "", Fence("```", "", 0), None)]
}

pub fn empty_fence_test() {
  assert parser.parse(["```txt info\n"], False)
    == [ClodBlock(1, [], "", Fence("```", "info", 0), None)]
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
      ClodBlock(
        4,
        [
          "\n",
          "code\n",
          "\n",
        ],
        "",
        Fence("```", "", 0),
        Some(Fence("```", "", 0)),
      ),
    ]
}
