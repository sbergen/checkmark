import checkmark/internal/caret
import gleam/int
import gleam/io
import gleam/string
import gleamy/bench

pub fn main() -> Nil {
  let long_input = long_string()
  let long_text = caret.from_string(long_input)
  bench.run(
    [
      bench.Input("long text", long_text),
    ],
    [
      bench.Function("to_string()", caret.to_string),
      bench.Function("to_string_alt()", caret.to_string_alt),
    ],
    [bench.Duration(1000), bench.Warmup(100)],
  )
  |> bench.table([bench.IPS, bench.Min, bench.P(99)])
  |> io.println()
}

fn long_string() -> String {
  int.range(0, 10_000, "", fn(result, _) { result <> long_line() <> "\n" })
}

fn long_line() -> String {
  let length = 80 + int.random(80)
  int.range(0, length, [], fn(result, _) { [random_character(), ..result] })
  |> string.from_utf_codepoints()
}

fn random_character() -> UtfCodepoint {
  let assert Ok(cp) = string.utf_codepoint(32 + int.random(94))
  cp
}
