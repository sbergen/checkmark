import glance.{type Module, type Span}
import gleam/bit_array
import gleam/list
import gleam/result

pub type ExtractError {
  FunctionNotFound(name: String)
  SpanExtractionFailed
}

pub opaque type File {
  Source(text: BitArray, module: Module)
}

pub fn load(source: String) -> Result(File, Nil) {
  use module <- result.map(glance.module(source) |> result.replace_error(Nil))
  Source(bit_array.from_string(source), module)
}

pub fn extract_function(
  file: File,
  name: String,
) -> Result(String, ExtractError) {
  use function <- result.try(
    file.module.functions
    |> list.map(fn(definition) { definition.definition })
    |> list.find(fn(f) { f.name == name })
    |> result.replace_error(FunctionNotFound(name)),
  )

  extract_source(file, function.location)
}

fn extract_source(file: File, span: Span) -> Result(String, ExtractError) {
  file.text
  |> bit_array.slice(span.start, span.end - span.start)
  |> result.try(bit_array.to_string)
  |> result.replace_error(SpanExtractionFailed)
}
