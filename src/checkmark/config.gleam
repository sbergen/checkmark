import checkmark/internal/code_extractor.{type CodeSegment}
import gleam/dict.{type Dict}
import gleam/int
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/result
import gleam/string
import tom.{type Toml}

pub type Expectation {
  ContentsOfFile(tag: String, filename: String)
  CodeSegment(tag: String, filename: String, segment: CodeSegment)
}

pub type Target {
  Target(name: String, path: String)
}

pub type ParseError =
  List(String)

pub type ParseResult(a) =
  Result(a, ParseError)

pub type Config =
  Dict(Target, List(Expectation))

pub fn parse(toml: String) -> ParseResult(Config) {
  use toml <- result.try(
    tom.parse(toml)
    |> result.map_error(fn(e) {
      let details = case e {
        tom.KeyAlreadyInUse(key:) ->
          "Key already in use: " <> string.join(key, ".")
        tom.Unexpected(got:, expected:) ->
          "Unexpected character: got: " <> got <> ", expected: " <> expected
      }

      ["Invalid TOML: " <> details]
    }),
  )

  // Currently all top level keys are targets
  let targets = dict.keys(toml)

  let #(targets, errors) = {
    use #(targets, errors), target <- list.fold(targets, #(
      dict.new(),
      list.new(),
    ))

    case parse_target(target, toml) {
      Ok(#(target, expectations)) -> #(
        dict.insert(targets, target, expectations),
        errors,
      )
      Error(new_errors) -> #(targets, list.append(errors, new_errors))
    }
  }

  case errors {
    [] -> Ok(targets)
    errors -> Error(errors)
  }
}

fn parse_target(
  name: String,
  toml: Dict(String, Toml),
) -> ParseResult(#(Target, List(Expectation))) {
  let context = TopLevel

  let sources_path = [name, "sources"]
  let sources =
    tom.get_array(toml, sources_path)
    |> map_get_error(context)
    |> result.try(fn(sources) {
      {
        use source, index <- list.index_map(sources)
        let context = array_contex(context, sources_path, index)
        use source <- result.try(tom.as_table(source) |> map_get_error(context))
        parse_source(source, context)
      }
      |> collect_errors()
    })
    |> result.map(list.flatten)

  let path = tom.get_string(toml, [name, "path"]) |> map_get_error(context)

  use sources, path <- merge_results2(sources, path)
  #(Target(name, path), sources)
}

fn parse_source(
  toml: Dict(String, Toml),
  context: ErrorContext,
) -> ParseResult(List(Expectation)) {
  // Path is always required
  let path = tom.get_string(toml, ["path"]) |> map_get_error(context)

  // Snippets and tag are mutually exclusive
  let snippets = parse_snippets(toml, context)
  let tag = tom.get_string(toml, ["tag"])

  let _ = case snippets, tag, path {
    // No snippets, use entire contents of file
    Ok(None), tag, path -> {
      use tag, path <- merge_results2(tag |> map_get_error(context), path)
      [ContentsOfFile(tag, path)]
    }

    // There are snippets and a tag, this is not allowed!
    Ok(_), Ok(_), path -> {
      let error =
        "'"
        <> context_to_prefix(context)
        <> "tag'"
        <> " must not be specified together with 'snippets'"

      // Merge with other errors, if any:
      case path {
        Error(errors) -> Error([error, ..errors])
        Ok(_) -> Error([error])
      }
    }

    Ok(Some(snippets)), Error(tom.NotFound(..)), Ok(path) ->
      Ok({
        use #(tag, segment) <- list.map(snippets)
        CodeSegment(tag, path, segment)
      })

    _, _, _ ->
      Error(
        list.new()
        |> collect_error(snippets)
        |> collect_error(tag |> map_get_error(context))
        |> collect_error(path),
      )
  }
}

fn parse_snippets(
  toml: Dict(String, Toml),
  context: ErrorContext,
) -> ParseResult(Option(List(#(String, CodeSegment)))) {
  let snippets_path = ["snippets"]

  let snippets =
    tom.get_array(toml, snippets_path)
    |> result.map(fn(snippets) {
      {
        use snippet, index <- list.index_map(snippets)
        let context = array_contex(context, snippets_path, index)
        use snippet <- result.try(
          tom.as_table(snippet) |> map_get_error(context),
        )
        parse_snippet(snippet, context)
      }
      |> collect_errors()
    })

  case snippets {
    Error(tom.NotFound(..)) -> Ok(None)
    Error(e) -> Error(to_parse_error(e, context))
    Ok(Ok(snippets)) -> Ok(Some(snippets))
    Ok(Error(e)) -> Error(e)
  }
}

fn parse_snippet(
  toml: Dict(String, Toml),
  context: ErrorContext,
) -> ParseResult(#(String, CodeSegment)) {
  // tag is required
  let tag = tom.get_string(toml, ["tag"]) |> map_get_error(context)

  // The others are mutually exclusive
  let function = tom.get_string(toml, ["function"])
  let function_body = tom.get_string(toml, ["function_body"])
  let type_definition = tom.get_string(toml, ["type"])
  let type_alias = tom.get_string(toml, ["type_alias"])

  let segment = case function, function_body, type_definition, type_alias {
    Ok(name),
      Error(tom.NotFound(..)),
      Error(tom.NotFound(..)),
      Error(tom.NotFound(..))
    -> Ok(code_extractor.Function(name))

    Error(tom.NotFound(..)),
      Ok(name),
      Error(tom.NotFound(..)),
      Error(tom.NotFound(..))
    -> Ok(code_extractor.FunctionBody(name))

    Error(tom.NotFound(..)),
      Error(tom.NotFound(..)),
      Ok(name),
      Error(tom.NotFound(..))
    -> Ok(code_extractor.TypeDefinition(name))

    Error(tom.NotFound(..)),
      Error(tom.NotFound(..)),
      Error(tom.NotFound(..)),
      Ok(name)
    -> Ok(code_extractor.TypeAlias(name))

    _, _, _, _ -> {
      let errors =
        list.new()
        |> collect_optional_error(context, function)
        |> collect_optional_error(context, function_body)
        |> collect_optional_error(context, type_definition)
        |> collect_optional_error(context, type_alias)

      case errors {
        [] ->
          Error([
            "'"
            <> context_to_prefix(context)
            <> "' must define only one of 'function', 'function_body', 'type', or 'type_alias'",
          ])
        errors -> Error(errors)
      }
    }
  }

  use tag, segment <- merge_results2(tag, segment)
  #(tag, segment)
}

fn collect_errors(results: List(Result(a, List(e)))) -> Result(List(a), List(e)) {
  let #(values, errors) = result.partition(results)
  case errors {
    [] -> Ok(values)
    errors -> Error(list.flatten(errors))
  }
}

fn collect_optional_error(
  errors: ParseError,
  context: ErrorContext,
  result: Result(a, tom.GetError),
) -> ParseError {
  case result {
    Ok(_) -> errors
    Error(tom.NotFound(..)) -> errors
    Error(e) -> list.append(to_parse_error(e, context), errors)
  }
}

fn collect_error(errors: List(e), result: Result(a, List(e))) -> List(e) {
  case result {
    Error(new_errors) -> list.append(errors, new_errors)
    Ok(_) -> errors
  }
}

fn merge_results2(
  a: ParseResult(a),
  b: ParseResult(b),
  merge: fn(a, b) -> c,
) -> ParseResult(c) {
  case a, b {
    Ok(a), Ok(b) -> Ok(merge(a, b))
    Error(e1), Error(e2) -> Error(list.append(e1, e2))
    Ok(_), Error(e) -> Error(e)
    Error(e), Ok(_) -> Error(e)
  }
}

type ErrorContext {
  TopLevel
  Nested(String)
}

fn array_contex(
  context: ErrorContext,
  path: List(String),
  index: Int,
) -> ErrorContext {
  let new = string.join(path, ".") <> "[" <> int.to_string(index) <> "]."
  Nested(context_to_prefix(context) <> new)
}

fn context_to_prefix(context: ErrorContext) -> String {
  case context {
    TopLevel -> ""
    Nested(ctx) -> ctx
  }
}

fn map_get_error(
  result: Result(a, tom.GetError),
  context: ErrorContext,
) -> ParseResult(a) {
  result.map_error(result, to_parse_error(_, context))
}

fn to_parse_error(error: tom.GetError, context: ErrorContext) -> ParseError {
  let path =
    "'" <> context_to_prefix(context) <> string.join(error.key, ".") <> "'"

  [
    case error {
      tom.NotFound(..) -> "Expected " <> path <> " to be specified"
      tom.WrongType(expected:, got:, ..) ->
        "Expected " <> path <> " to be " <> expected <> " found " <> got
    },
  ]
}
