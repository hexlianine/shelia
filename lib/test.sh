# shellcheck shell=bash
# Test helpers (SRP: minimal assertions and test runner helpers).

# shellcheck source=./logging.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/logging.sh"

# shellcheck source=./shell.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/shell.sh"
shelia::shell::begin_module TEST_HELPERS || return 0

function shelia::test::init() {
  if [[ -z "${SHELIA_TEST_DIR:-}" ]]; then
    SHELIA_TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[1]}")" && pwd)"
  fi

  if [[ -z "${ROOT_DIR:-}" ]]; then
    ROOT_DIR="$(cd "${SHELIA_TEST_DIR}/.." && pwd)"
  fi

  : "${SHELIA_TEST_FAILURES:=0}"
}

function shelia::test::fail() {
  shelia::logging::error "FAIL: $1"
  SHELIA_TEST_FAILURES=$((SHELIA_TEST_FAILURES + 1))
}

function shelia::test::pass() {
  shelia::logging::info "PASS: $1"
}

function shelia::test::assert_eq() {
  local expected="$1"
  local actual="$2"
  local context="$3"
  if [[ "$expected" != "$actual" ]]; then
    shelia::test::fail "${context} (expected: ${expected}, got: ${actual})"
    return 1
  fi
  return 0
}

function shelia::test::assert_contains() {
  local haystack="$1"
  local needle="$2"
  local context="$3"
  if [[ "$haystack" != *"$needle"* ]]; then
    shelia::test::fail "${context} (missing: ${needle})"
    return 1
  fi
  return 0
}

function shelia::test::assert_not_contains() {
  local haystack="$1"
  local needle="$2"
  local context="$3"
  if [[ "$haystack" == *"$needle"* ]]; then
    shelia::test::fail "${context} (unexpected: ${needle})"
    return 1
  fi
  return 0
}

function shelia::test::run_test() {
  local name="$1"
  shift 1
  local before="$SHELIA_TEST_FAILURES"
  if "$@"; then
    shelia::test::pass "$name"
  else
    if [[ "$SHELIA_TEST_FAILURES" -eq "$before" ]]; then
      shelia::test::fail "$name"
    else
      shelia::logging::error "FAIL: $name"
    fi
  fi
}

function shelia::test::failures() {
  shelia::logging::info '%s' "${SHELIA_TEST_FAILURES:-0}"
}
