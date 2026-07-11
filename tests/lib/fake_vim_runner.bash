#!/usr/bin/env bash
set -euo pipefail

[[ "${RUN_MODE:-}" == "${EXPECT_RUN_MODE:-}" ]] || {
  echo "expected RUN_MODE=${EXPECT_RUN_MODE:-}, got ${RUN_MODE:-}" >&2
  exit 1
}

if [[ -n "${EXPECT_TARGET_CONTAINS:-}" ]]; then
  [[ "${RUN_TARGET:-}" == *"$EXPECT_TARGET_CONTAINS"* ]] || {
    echo "RUN_TARGET does not contain $EXPECT_TARGET_CONTAINS: ${RUN_TARGET:-}" >&2
    exit 1
  }
fi

if [[ -n "${EXPECT_FILE_CONTAINS:-}" ]]; then
  grep -Fq "$EXPECT_FILE_CONTAINS" "$RUN_TARGET" || {
    echo "filtered target does not contain: $EXPECT_FILE_CONTAINS" >&2
    exit 1
  }
fi

if [[ -n "${EXPECT_FILE_CONTAINS_2:-}" ]]; then
  grep -Fq "$EXPECT_FILE_CONTAINS_2" "$RUN_TARGET" || {
    echo "filtered target does not contain: $EXPECT_FILE_CONTAINS_2" >&2
    exit 1
  }
fi

if [[ -n "${EXPECT_FILE_EXCLUDES:-}" ]]; then
  ! grep -Fq "$EXPECT_FILE_EXCLUDES" "$RUN_TARGET" || {
    echo "filtered target unexpectedly contains: $EXPECT_FILE_EXCLUDES" >&2
    exit 1
  }
fi

if [[ -n "${EXPECT_LISTED_FILE_CONTAINS:-}" ]]; then
  listed_file="$(sed -n '1p' "$RUN_TARGET")"
  grep -Fq "$EXPECT_LISTED_FILE_CONTAINS" "$listed_file" || {
    echo "listed target does not contain: $EXPECT_LISTED_FILE_CONTAINS" >&2
    exit 1
  }
fi

if [[ -n "${EXPECT_LISTED_FILE_CONTAINS_2:-}" ]]; then
  listed_file="$(sed -n '1p' "$RUN_TARGET")"
  grep -Fq "$EXPECT_LISTED_FILE_CONTAINS_2" "$listed_file" || {
    echo "listed target does not contain: $EXPECT_LISTED_FILE_CONTAINS_2" >&2
    exit 1
  }
fi
