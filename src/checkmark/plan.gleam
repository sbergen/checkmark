//// TODO: docs

import checkmark/config
import gleam/dict
import gleam/list
import gleam/set.{type Set}

pub opaque type Plan {
  Plan(config: config.Config)
}

pub type Replacement {
  Replacement(
    filename: String,
    from_line: Int,
    to_line: Int,
    new_lines: List(String),
  )
}

pub fn inputs(plan: Plan) -> Set(String) {
  use inputs, _filename, expectations <- dict.fold(plan.config, set.new())
  use inputs, expectation <- list.fold(expectations, inputs)
  set.insert(inputs, expectation.filename)
}
