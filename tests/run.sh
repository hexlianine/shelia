#!/usr/bin/env bash
# shellcheck shell=bash

# Re-exec with a compliant Bash (4.3+) if the current shell is too old.
# shellcheck source=../lib/bootstrap.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/../lib/bootstrap.sh"
shelia::bootstrap::ensure "${BASH_SOURCE[0]}" "$@"

# shellcheck source=../lib/logging.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/../lib/logging.sh"

set -u

SHELIA_TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

failures=0

for test_file in "${SHELIA_TEST_DIR}"/*_test.sh; do
  if [[ ! -f "$test_file" ]]; then
    continue
  fi
  if "$BASH" "$test_file"; then
    continue
  fi
  failures=$((failures + 1))
done

if [[ "$failures" -gt 0 ]]; then
  shelia::logging::error "$failures test(s) failed."
  exit 1
fi

shelia::logging::info "All test suites passed."
