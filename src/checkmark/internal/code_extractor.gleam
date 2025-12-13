import checkmark/internal/lines.{to_lines}
import glance.{type Module, type Span, Span}
import gleam/bit_array
import gleam/bool
import gleam/list
import gleam/result
import splitter.{type Splitter}

pub type ExtractError {
  NameNotFound(name: String)
  SpanExtractionFailed
}

pub opaque type File {
  Source(text: BitArray, module: Module, line_ends: Splitter)
}

pub fn load(source: String) -> Result(File, Nil) {
  use module <- result.map(glance.module(source) |> result.replace_error(Nil))
  let line_ends = splitter.new(["\n", "\r\n"])
  Source(bit_array.from_string(source), module, line_ends:)
}

pub fn extract_function(
  file: File,
  name: String,
) -> Result(List(String), ExtractError) {
  use function <- result.try(find_function(file, name))
  extract_source(file, function.location)
}

pub fn extract_function_body(
  file: File,
  name: String,
) -> Result(List(String), ExtractError) {
  use function <- result.try(find_function(file, name))
  let span =
    list.first(function.body)
    |> result.map(fn(first) {
      let assert Ok(last) = list.last(function.body)
      Span(statement_span(first).start, statement_span(last).end)
    })

  use indented <- result.try(case span {
    // no statements!
    Error(_) -> Ok([])
    Ok(span) -> extract_source(file, span)
  })

  Ok(unindent(indented))
}

pub fn extract_type(
  file: File,
  name: String,
) -> Result(List(String), ExtractError) {
  use function <- result.try(find_type(file, name))
  extract_source(file, function.location)
}

pub fn extract_type_alias(
  file: File,
  name: String,
) -> Result(List(String), ExtractError) {
  use alias <- result.try(find_type_alias(file, name))
  extract_source(file, alias.location)
}

fn unindent(indented: List(String)) -> List(String) {
  let indent_amount =
    list.first(indented)
    |> result.map(indent_amount(_, 0))
    |> result.unwrap(0)

  use line <- list.map(indented)
  remove_space(line, indent_amount)
}

fn remove_space(string: String, up_to: Int) -> String {
  case up_to, string {
    _, " " <> rest if up_to > 0 -> remove_space(rest, up_to - 1)
    _, _ -> string
  }
}

fn indent_amount(string: String, amount: Int) -> Int {
  case string {
    " " <> rest -> indent_amount(rest, amount + 1)
    _ -> amount
  }
}

fn statement_span(statement: glance.Statement) -> Span {
  case statement {
    glance.Expression(expr) -> expr.location
    glance.Assert(location:, ..) -> location
    glance.Assignment(location:, ..) -> location
    glance.Use(location:, ..) -> location
  }
}

fn find_function(
  file: File,
  name: String,
) -> Result(glance.Function, ExtractError) {
  file.module.functions
  |> list.map(fn(definition) { definition.definition })
  |> list.find(fn(f) { f.name == name })
  |> result.replace_error(NameNotFound(name))
}

fn find_type(
  file: File,
  name: String,
) -> Result(glance.CustomType, ExtractError) {
  file.module.custom_types
  |> list.map(fn(definition) { definition.definition })
  |> list.find(fn(f) { f.name == name })
  |> result.replace_error(NameNotFound(name))
}

fn find_type_alias(
  file: File,
  name: String,
) -> Result(glance.TypeAlias, ExtractError) {
  file.module.type_aliases
  |> list.map(fn(definition) { definition.definition })
  |> list.find(fn(f) { f.name == name })
  |> result.replace_error(NameNotFound(name))
}

fn extract_source(file: File, span: Span) -> Result(List(String), ExtractError) {
  let start = include_leading_space(file.text, span.start)
  let end = include_trailing_space(file.text, span.end)

  file.text
  |> bit_array.slice(start, end - start)
  |> result.try(bit_array.to_string)
  |> result.map(to_lines(file.line_ends, _, []))
  |> result.replace_error(SpanExtractionFailed)
}

fn include_leading_space(bits: BitArray, position: Int) -> Int {
  use <- bool.guard(position == 0, position)
  let checked = position - 1
  case bit_array.slice(bits, checked, 1) {
    Ok(<<" ">>) -> include_leading_space(bits, checked)
    _ -> position
  }
}

fn include_trailing_space(bits: BitArray, position: Int) -> Int {
  case bit_array.slice(bits, position, 1) {
    Ok(<<" ">>) | Ok(<<"\r">>) | Ok(<<"\n">>) ->
      include_trailing_space(bits, position + 1)
    _ -> position
  }
}
