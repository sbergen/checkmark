# Changelog

## Unreleased

### Deprecated
- `file` was deprecated for clarity reasons. Use `document` instead.

### Added

- Adds support for replacing snippets in code comments,
  using `comments_in` instead of `document`.

## v2.0.0 - 2025-08-02

This is a complete rewrite. Instead of checking or running gleam code via checkmark,
checkmark can now either check that a snippet matches the content in a file,
or update the markdown file with the content.

Dependencies have also been simplified, and the parsing of the markdown file
no longer uses the package it used to, as it had some issues in it,
and doesn't seem to be actively maintained.

## v1.0.0 - 2024-11-25

### Added

- `print_failures` can be used to pretty-print any errors, and optionally panic.
  This is especially useful on the Erlang runtime, as it ugly-prints most Gleam compiler output.


## v0.1.0 - 2024-11-10

Initial release
