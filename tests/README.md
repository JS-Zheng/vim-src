# Tests

This directory is the canonical home for `vim-src` test tooling, fixtures, and
test suites.

If you want to understand how to run or extend the test suite, start here.

The actual test scripts live in `tests/`. For day-to-day convenience, the repo
root `Makefile` exposes common shortcuts. `scripts/` is not part of the
maintained test interface.

## Entry Points

- `tests/run`
  - canonical test runner
- `tests/setup`
  - canonical local bootstrap for `vader.vim`

Convenience commands:

- `make setup`
- `make test`
- `make test-all`
- `make list-suites`
- `make list-cases SUITE=<suite>`

## Common Commands

Fast local TDD loop:

```sh
make test SUITE=src_command
make test SUITE=src_command CASE="modified named buffer"

tests/run --suite src_command
tests/run --suite src_command --case "modified named buffer"
```

Run the full suite:

```sh
make test-all

tests/run
```

Run one suite:

```sh
tests/run src_command
tests/run --suite src_command
```

Run multiple suites:

```sh
tests/run --suite src_command --suite src_optionality
```

Run matching case(s) across all suites:

```sh
tests/run --case "modified named buffer"
```

Run multiple case filters together:

```sh
tests/run --suite src_command --case "modified named buffer" --case "quoted path"
```

Run matching case(s) inside one suite:

```sh
tests/run --suite src_command --case "modified named buffer"
```

List suites:

```sh
tests/run --list-suites
```

List cases in one suite:

```sh
tests/run --list-cases src_command
```

## Case Filtering

Case filtering is based on substring matching against `Execute` / `Do` header
lines in `.vader` files.

When `--case` is used, `tests/run` generates temporary filtered suites that
preserve global `Before`, `After`, `Given`, and `Include` blocks together with
the matching cases.

This is intended to support fast TDD loops without running the full suite on
every edit.

Multiple `--case` options are allowed. A case is selected when any given
substring matches its `Execute` / `Do` header.

## Directory Structure

```text
tests/
  README.md
  run
  setup
  lib/
    filter_vader_case.awk
    test_helper.vim
  fixtures/
  suites/
    shared/
    unix/
    windows/
```

### `tests/suites`

Contract suites. `shared/` is cross-platform, `unix/` is Unix-only, and
`windows/` is Windows-only. Each file should own one coherent public behavior
area without in-suite OS branching.

### `tests/fixtures`

Tracked filesystem fixtures grouped by behavior area.

### `tests/lib`

Small support files for test infrastructure and narrow test-only utilities.

### `tests/lib/test_helper.vim`

Narrow Vimscript helpers for exceptional cases where pure decision logic is hard
to validate cleanly through public APIs alone.

## Maintenance Rules

- Prefer `tests/` as the home of actual test scripts and support files.
- Prefer `make` for everyday convenience, or `tests/run` when you need the
  exact runner entrypoint.
- Prefer public API tests over internal helper tests.
- Add new fixtures only when they make intent clearer.
- Keep case names behavioral and specific so `--case` remains useful.
- During ordinary development, prefer targeted suite/case runs.
- Reserve full-suite runs for milestone checks and broader integration changes.
