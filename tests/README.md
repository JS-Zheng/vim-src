# Tests

This directory is the canonical home for `vim-src` test tooling, fixtures, and
test suites.

The test runner is implemented once, in `tests/run.py`, and supports Python 3.8
or newer. `tests/run` is a thin wrapper around it (set `PYTHON` to choose the
interpreter).

`tests/runner_contract.bash` supports the macOS system Bash baseline: Bash 3.2
or newer. Do not introduce associative arrays, `mapfile`, case-changing
parameter expansion, or other Bash 4+ syntax there.

If you want to understand how to run or extend the test suite, start here.

The actual test scripts live in `tests/`. For day-to-day convenience, the repo
root `Makefile` exposes common shortcuts.

## Entry Points

- `tests/run`
  - canonical test runner entry point (wraps `tests/run.py`)
- `tests/run.py`
  - the runner itself; call it directly on Windows
- `tests/setup`
  - canonical local bootstrap for `vader.vim`
- `tests/runner_contract.bash`
  - black-box runner selection/filtering contracts, run by `make test-runner`

Convenience commands:

- `make setup`
- `make test`
- `make test-runner`
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

On Windows, check out `vader.vim` into `.deps/vader.vim` and call the runner
directly:

```sh
python tests/run.py
python tests/run.py --suite src_command --case "modified named buffer"
```

`VIM_BIN` selects the editor, for example `VIM_BIN=nvim`. `SUITE` and `CASE`
environment variables add one suite or case pattern, as `make test` passes them.

Inspect generated runner state and retain temporary artifacts:

```sh
make test-debug

DEBUG=1 KEEP_TMP=1 tests/run --suite src_command
```

`DEBUG=1` prints the resolved editor command, mode, target, temporary path, and
generated Vimscript. `KEEP_TMP=1` preserves that directory after exit; either
flag can be used independently.

Validate runner selection/filtering contracts without launching the real editor:

```sh
make test-runner
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

When `--case` is used, the runner generates temporary filtered suites that
preserve global `Before`, `After`, and `Given` blocks together with matching
cases. Plain and typed `Include` macros are preserved with paths resolved
relative to the original suite. Their referenced files must be setup/cleanup
fragments without test cases. Case-bearing, nested, or unresolvable includes
fail before Vim starts. Empty `--case` patterns are rejected.

This is intended to support fast TDD loops without running the full suite on
every edit.

Multiple `--case` options are allowed. A case is selected when any given
substring matches its `Execute` / `Do` header.

## Directory Structure

```text
tests/
  README.md
  run
  run.py
  runner_contract.bash
  setup
  lib/
    fake_vim_runner.bash
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
