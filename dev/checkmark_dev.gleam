import checkmark/internal/caret
import gleam/int
import gleam/io
import gleam/string
import gleamy/bench.{type Function, type Input}

pub fn main() -> Nil {
  // The different representations here are useful for future benchmarks.
  let long_lines =
    int.range(0, 10_000, [], fn(result, _) { [long_line(), ..result] })
  let long_input = string.join(long_lines, "\n")
  let long_text = caret.from_string(long_input)

  benchmark(
    [
      bench.Input("long text", long_text),
    ],
    [
      bench.Function("to_string()", caret.to_string),
    ],
  )

  benchmark(
    [
      bench.Input("long input", long_input),
    ],
    [
      bench.Function("from_string()", caret.from_string),
    ],
  )
}

fn benchmark(inputs: List(Input(a)), functions: List(Function(a, b))) -> Nil {
  bench.run(inputs, functions, [bench.Duration(1000), bench.Warmup(100)])
  |> bench.table([bench.IPS, bench.Min, bench.P(99)])
  |> io.println()
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
