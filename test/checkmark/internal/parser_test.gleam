import checkmark/internal/caret
import checkmark/internal/parser.{CodeBlock, Fence}
import gleam/option.{None, Some}

fn comment_agnostic(body: fn(Bool) -> Nil) -> Nil {
  body(False)
  body(True)
}

pub fn empty_string_test() {
  use in_comments <- comment_agnostic()
  assert parser.parse(caret.from_string(""), in_comments) == []
}

pub fn no_snippets_test() {
  use in_comments <- comment_agnostic()

  let text =
    caret.from_string(
      "one
two
three",
    )
  assert parser.parse(text, in_comments) == []
}

pub fn basic_snippet_test() {
  assert parser.parse(
      caret.from_string(
        "start
```gleam tag 
code
more_code
``` 
rest",
      ),
      False,
    )
    == [
      CodeBlock(
        2,
        caret.from_string(
          "code
more_code",
        ),
        "",
        Fence("```", "tag", 0),
        Some(Fence("```", "", 0)),
      ),
    ]
}

pub fn doc_comment_test() {
  assert parser.parse(
      caret.from_string(
        "pub const answer = 42

/// start
/// ```gleam   tag 
/// code
/// more_code
/// ``` 
pub const answer_str = \"*\"",
      ),
      True,
    )
    == [
      CodeBlock(
        4,
        caret.from_string(
          "code
more_code",
        ),
        "/// ",
        Fence("```", "tag", 0),
        Some(Fence("```", "", 0)),
      ),
    ]
}

pub fn module_comment_test() {
  assert parser.parse(
      caret.from_string(
        "//// start
//// ```gleam
//// code
//// ``` 
//// rest",
      ),
      True,
    )
    == [
      CodeBlock(
        2,
        caret.from_string("code"),
        "//// ",
        Fence("```", "", 0),
        Some(Fence("```", "", 0)),
      ),
    ]
}

pub fn unfinished_comment_block_test() {
  let assert [CodeBlock(2, code, "//// ", Fence("```", "tag", 0), None)] =
    parser.parse(
      caret.from_string(
        "//// start
//// ```gleam tag
//// code
rest",
      ),
      True,
    )
  assert caret.to_string(code) == "code"
}

pub fn indented_snippet_test() {
  let assert [
    CodeBlock(1, code, "", Fence("```", "tag", 3), Some(Fence("```", "", 2))),
  ] =
    parser.parse(
      caret.from_string(
        "   ```gleam tag
   code
     more_code
 not indented enough
  ```",
      ),
      False,
    )
  assert caret.to_string(code) == "code
  more_code
not indented enough"
}

pub fn non_matching_fences_test() {
  assert parser.parse(
      caret.from_string(
        "````
```
~~~
code
````",
      ),
      False,
    )
    == [
      CodeBlock(
        1,
        caret.from_string(
          "```
~~~
code",
        ),
        "",
        Fence("````", "", 0),
        Some(Fence("````", "", 0)),
      ),
    ]
}

pub fn missing_end_fence_test() {
  let assert [CodeBlock(1, code, "", Fence("```", "", 0), None)] =
    parser.parse(
      caret.from_string(
        "```
code",
      ),
      False,
    )
  assert caret.to_string(code) == "code"
}

pub fn empty_fence_test() {
  let assert [CodeBlock(1, code, "", Fence("```", "info", 0), None)] =
    parser.parse(caret.from_string("```txt info\n"), False)
  assert caret.to_string(code) == ""
}

pub fn emtpy_line_preservation_test() {
  let assert [
    CodeBlock(3, code, "", Fence("```", "", 0), Some(Fence("```", "", 0))),
  ] =
    parser.parse(
      caret.from_string(
        "text

```

code

```
",
      ),
      False,
    )

  assert caret.to_string(code) == "\ncode\n"
}
