#!/usr/bin/env bash
# shellcheck shell=bash

set -u

# shellcheck source=../lib/logging.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/../lib/logging.sh"

# shellcheck source=../lib/test.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/../lib/test.sh"
shelia::test::init

shelia::logging::info "Logging tests start (All colors stubbed)"

stub_colors() {
  shelia::color::debug() { printf '%s' "$1"; }
  shelia::color::info() { printf '%s' "$1"; }
  shelia::color::warning() { printf '%s' "$1"; }
  shelia::color::failure() { printf '%s' "$1"; }
}

source_logging() {
  if ! declare -F shelia::shell::begin_module >/dev/null 2>&1; then
    shelia::shell::begin_module() { return 0; }
  fi
  # shellcheck source=../lib/logging.sh
  source "${ROOT_DIR}/lib/logging.sh"
  trap - ERR
  set +e
  set +u
  set +o pipefail
  stub_colors
}

test_log_without_file() {
  source_logging
  SHELIA_LOG_FILE=""
  local output
  output=$(shelia::logging::log "hello")
  shelia::test::assert_eq "hello" "$output" "log without file outputs message"
}

test_log_with_file() {
  source_logging
  local tmpfile
  tmpfile="$(mktemp)"
  : >"$tmpfile"
  SHELIA_LOG_FILE="$tmpfile"
  local output
  output=$(shelia::logging::log "hi")
  shelia::test::assert_eq "hi" "$output" "log with file outputs message"
  local last_line
  last_line="$(tail -n 1 "$tmpfile")"
  shelia::test::assert_eq "hi" "$last_line" "log with file appends message"
}

test_construct_backtrace() {
  source_logging
  local output
  level1() { level2; }
  level2() { shelia::logging::construct_backtrace; }
  output="$(level1)"
  shelia::test::assert_contains "$output" "level2" "backtrace includes inner function"
  shelia::test::assert_contains "$output" "level1" "backtrace includes outer function"
  shelia::test::assert_not_contains "$output" "shelia::logging::construct_backtrace" "backtrace excludes helper"
}

test_construct_log_kind_info() {
  source_logging
  date() { printf '%s\n' '2020-01-01T00:00:00Z'; }
  local output
  outer() { inner; }
  inner() { shelia::logging::construct_log_kind_info; }
  output="$(outer)"
  shelia::test::assert_contains "$output" "2020-01-01T00:00:00Z" "log kind includes timestamp"
  shelia::test::assert_contains "$output" "$(basename "${BASH_SOURCE[0]}")" "log kind includes filename"
  local function_name
  function_name="$(printf '%s' "$output" | awk -F ' - ' '{print $2}')"
  if [[ -z "$function_name" ]]; then
    shelia::test::fail "log kind includes caller name"
    return 1
  fi
}

test_debug_info_warn_error() {
  source_logging
  SHELIA_LOG_FILE=""
  local debug_out info_out warn_out error_out
  debug_out="$(shelia::logging::debug "dbg")"
  info_out="$(shelia::logging::info "info")"
  warn_out="$(shelia::logging::warn "warn")"
  error_out="$(shelia::logging::error "boom")"

  shelia::test::assert_contains "$debug_out" "[DEBUG]" "debug prefix"
  shelia::test::assert_contains "$info_out" "[INFO]" "info prefix"
  shelia::test::assert_contains "$warn_out" "[WARNING]" "warning prefix"
  shelia::test::assert_contains "$error_out" "[ERROR]" "error prefix"
  shelia::test::assert_contains "$error_out" "CURRENT DIR:" "error includes current dir"
  shelia::test::assert_contains "$error_out" "boom" "error includes message"
}

test_error_handler_exits_and_logs() {
  local output
  local exit_code
  output=$( (
    source_logging
    shelia::logging::log() { printf '%s' "$1"; }
    false
    error_handler 123
  ))
  exit_code=$?

  shelia::test::assert_eq "1" "$exit_code" "error_handler exits with status"
  shelia::test::assert_contains "$output" "ERROR: Command failed" "error_handler logs error"
  shelia::test::assert_contains "$output" "Exit code: 1" "error_handler logs exit code"
  shelia::test::assert_contains "$output" "Command:" "error_handler logs command"
}

shelia::test::run_test "log without file" test_log_without_file
shelia::test::run_test "log with file" test_log_with_file
shelia::test::run_test "construct backtrace" test_construct_backtrace
shelia::test::run_test "construct log kind info" test_construct_log_kind_info
shelia::test::run_test "debug/info/warn/error" test_debug_info_warn_error
shelia::test::run_test "error handler exits and logs" test_error_handler_exits_and_logs

if [[ "${SHELIA_TEST_FAILURES:-0}" -gt 0 ]]; then
  shelia::logging::error "%s test(s) failed." "${SHELIA_TEST_FAILURES}"
  exit 1
fi

shelia::logging::info "All tests passed."
