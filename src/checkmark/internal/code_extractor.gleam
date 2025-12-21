import checkmark/internal/caret.{type Text}
import glance.{type Module, type Span, Span}
import gleam/bit_array
import gleam/bool
import gleam/list
import gleam/result
import splitter.{type Splitter}

pub type ExtractError {
  NameNotFound(name: String)
  SpanExtractionFailed(name: String)
}

pub type CodeSegment {
  Function(name: String)
  FunctionBody(name: String)
  TypeDefinition(name: String)
  TypeAlias(name: String)
}

pub opaque type File {
  Source(text: BitArray, module: Module, line_ends: Splitter)
}

pub fn load(source: String) -> Result(File, Nil) {
  // glance errors are hard to format,
  // and errors here aren't really for us to deal with - let the compiler report them.
  use module <- result.map(glance.module(source) |> result.replace_error(Nil))
  let line_ends = splitter.new(["\n", "\r\n"])
  Source(bit_array.from_string(source), module, line_ends:)
}

pub fn extract(file: File, segment: CodeSegment) -> Result(Text, ExtractError) {
  case segment {
    Function(name:) -> {
      use function <- result.try(find_function(file, name))
      extract_source(file, function.location, segment.name)
    }

    TypeAlias(name:) -> {
      use alias <- result.try(find_type_alias(file, name))
      extract_source(file, alias.location, segment.name)
    }

    TypeDefinition(name:) -> {
      use function <- result.try(find_type(file, name))
      extract_source(file, function.location, segment.name)
    }

    FunctionBody(name:) -> extract_function_body(file, name)
  }
}

fn extract_function_body(file: File, name: String) -> Result(Text, ExtractError) {
  use function <- result.try(find_function(file, name))
  let span =
    list.first(function.body)
    |> result.map(fn(first) {
      let assert Ok(last) = list.last(function.body)
      Span(statement_span(first).start, statement_span(last).end)
    })

  use indented <- result.try(case span {
    // no statements!
    Error(_) -> Ok(caret.from_string(""))
    Ok(span) -> extract_source(file, span, name)
  })

  Ok(indented |> caret.auto_unindent)
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

fn extract_source(
  file: File,
  span: Span,
  name: String,
) -> Result(Text, ExtractError) {
  let start = include_leading_space(file.text, span.start)

  file.text
  |> bit_array.slice(start, span.end - start)
  |> result.try(bit_array.to_string)
  |> result.map(caret.from_string)
  |> result.replace_error(SpanExtractionFailed(name))
}

fn include_leading_space(bits: BitArray, position: Int) -> Int {
  use <- bool.guard(position == 0, position)
  let checked = position - 1
  case bit_array.slice(bits, checked, 1) {
    Ok(<<" ">>) -> include_leading_space(bits, checked)
    _ -> position
  }
}
