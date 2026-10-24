#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
TMP_DIR="$(mktemp -d)"
RETAINED_DIRS_FILE="$TMP_DIR/retained-dirs.txt"
: > "$RETAINED_DIRS_FILE"
cleanup() {
  while IFS= read -r dir; do
    [[ -n "$dir" ]] || continue
    rm -rf "$dir"
  done < "$RETAINED_DIRS_FILE"
  rm -rf "$TMP_DIR"
}
trap cleanup EXIT
trap 'exit 129' HUP
trap 'exit 130' INT
trap 'exit 143' TERM

mkdir -p "$TMP_DIR/vader.vim"
FAKE_VIM="$ROOT_DIR/tests/lib/fake_vim_runner.bash"

fail() {
  echo "runner contract failed: $*" >&2
  exit 1
}

assert_contains() {
  [[ "$1" == *"$2"* ]] || fail "expected output to contain: $2"
}

cd "$ROOT_DIR"

suites="$(tests/run --list-suites)"
assert_contains "$suites" "src_command"
if [[ "$(uname -s)" == MINGW* || "$(uname -s)" == MSYS* || "$(uname -s)" == CYGWIN* ]]; then
  assert_contains "$suites" "windows_path_contract"
else
  assert_contains "$suites" "symlink_resolution"
fi

cases="$(tests/run --list-cases src_command)"
assert_contains "$cases" "call src#() accepts a direct string path"

VADER_DIR="$TMP_DIR/vader.vim" \
VIM_BIN="$FAKE_VIM" \
EXPECT_RUN_MODE=glob \
EXPECT_TARGET_CONTAINS='tests/suites/shared/*.vader' \
tests/run

VADER_DIR="$TMP_DIR/vader.vim" \
VIM_BIN="$FAKE_VIM" \
EXPECT_RUN_MODE=file \
EXPECT_TARGET_CONTAINS=src_command.vader \
tests/run --suite src_command

VADER_DIR="$TMP_DIR/vader.vim" \
VIM_BIN="$FAKE_VIM" \
EXPECT_RUN_MODE=file \
EXPECT_FILE_CONTAINS="call src#() accepts a direct string path" \
EXPECT_FILE_EXCLUDES="call src#() accepts a one-item list target" \
tests/run --suite src_command --case "direct string path"

VADER_DIR="$TMP_DIR/vader.vim" \
VIM_BIN="$FAKE_VIM" \
EXPECT_RUN_MODE=list \
EXPECT_FILE_CONTAINS=src_command.vader \
EXPECT_FILE_CONTAINS_2=src_optionality.vader \
tests/run --suite src_command --suite src_optionality

VADER_DIR="$TMP_DIR/vader.vim" \
VIM_BIN="$FAKE_VIM" \
EXPECT_RUN_MODE=file \
EXPECT_FILE_CONTAINS="direct string path" \
EXPECT_FILE_CONTAINS_2="one-item list target" \
tests/run --suite src_command \
  --case "direct string path" --case "one-item list target"

VADER_DIR="$TMP_DIR/vader.vim" \
VIM_BIN="$FAKE_VIM" \
EXPECT_RUN_MODE=file \
EXPECT_TARGET_CONTAINS=src_command.vader \
tests/run tests/suites/shared/src_command.vader

debug_output="$(
  DEBUG=1 KEEP_TMP=1 \
  VADER_DIR="$TMP_DIR/vader.vim" \
  VIM_BIN="$FAKE_VIM" \
  EXPECT_RUN_MODE=file \
  EXPECT_TARGET_CONTAINS=src_command.vader \
  tests/run --suite src_command
)"
assert_contains "$debug_output" "RUN_MODE=file"
debug_tmp="$(printf '%s\n' "$debug_output" | awk -F= '/^TMP_DIR=/ {print $2; exit}')"
[[ -d "$debug_tmp" ]] || fail "debug temp directory was not retained"
printf '%s\n' "$debug_tmp" >> "$RETAINED_DIRS_FILE"

INCLUDE_SETUP="$TMP_DIR/include-setup.vader"
INCLUDE_CASES="$TMP_DIR/include-cases.vader"
INCLUDE_SUITE="$TMP_DIR/include-suite.vader"
printf '%s\n' 'Before:' '  let g:included_setup = 1' > "$INCLUDE_SETUP"
printf '%s\n' 'Execute (included case):' '  Assert 1' > "$INCLUDE_CASES"
printf 'Include: include-setup.vader\nExecute (selected case):\n  Assert 1\n' \
  > "$INCLUDE_SUITE"

VADER_DIR="$TMP_DIR/vader.vim" \
VIM_BIN="$FAKE_VIM" \
EXPECT_RUN_MODE=file \
EXPECT_FILE_CONTAINS='selected case' \
EXPECT_FILE_CONTAINS_2="$INCLUDE_SETUP" \
tests/run "$INCLUDE_SUITE" --case 'selected case'

printf 'Include (vim): include-setup.vader\nExecute (selected case):\n  Assert 1\n' \
  > "$INCLUDE_SUITE"
VADER_DIR="$TMP_DIR/vader.vim" \
VIM_BIN="$FAKE_VIM" \
EXPECT_RUN_MODE=file \
EXPECT_FILE_CONTAINS='Include (vim):' \
EXPECT_FILE_CONTAINS_2="$INCLUDE_SETUP" \
tests/run "$INCLUDE_SUITE" --case 'selected case'

printf 'Include: include-cases.vader\nExecute (selected case):\n  Assert 1\n' \
  > "$INCLUDE_SUITE"
INCLUDE_ERROR="$TMP_DIR/include-error.txt"
if VADER_DIR="$TMP_DIR/vader.vim" VIM_BIN="$FAKE_VIM" \
    tests/run "$INCLUDE_SUITE" --case 'selected case' 2> "$INCLUDE_ERROR"; then
  fail "case-bearing Include should fail before Vim starts"
fi
assert_contains "$(< "$INCLUDE_ERROR")" "included Vader file contains test cases"

EMPTY_CASE_ERROR="$TMP_DIR/empty-case-error.txt"
if VADER_DIR="$TMP_DIR/vader.vim" VIM_BIN="$FAKE_VIM" \
    tests/run --suite src_command --case '' 2> "$EMPTY_CASE_ERROR"; then
  fail "empty case pattern should fail"
fi
assert_contains "$(< "$EMPTY_CASE_ERROR")" "case pattern must not be empty"

NO_MATCH_ERROR="$TMP_DIR/no-match-error.txt"
if VADER_DIR="$TMP_DIR/vader.vim" VIM_BIN="$FAKE_VIM" \
    tests/run --suite src_command --case "definitely-not-a-case" \
    2> "$NO_MATCH_ERROR"; then
  fail "no-match case selection should fail"
fi
assert_contains "$(< "$NO_MATCH_ERROR")" "no test case matched"

# Windows runs the Python runner directly instead of through tests/run.
py_suites="$("${PYTHON:-python3}" tests/run.py --list-suites)"
assert_contains "$py_suites" "src_command"

echo "runner contracts: ok"
