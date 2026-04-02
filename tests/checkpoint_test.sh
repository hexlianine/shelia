#!/usr/bin/env bash
# shellcheck shell=bash

set -u

# shellcheck source=../lib/logging.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/../lib/logging.sh"

# shellcheck source=../lib/test.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/../lib/test.sh"
shelia::test::init

# shellcheck source=../lib/checkpoint.sh
source "${ROOT_DIR}/lib/checkpoint.sh"

# Test setup
TEST_TEMP_DIR=$(mktemp -d)
trap 'rm -rf "$TEST_TEMP_DIR"' EXIT

CHECKPOINT_FILE="${TEST_TEMP_DIR}/test.checkpoint"
export CHECKPOINT_FILE

test_init() {
  rm -f "$CHECKPOINT_FILE"
  # Should fail if file doesn't exist but returns 1 (as per implementation)
  shelia::checkpoint::init "$CHECKPOINT_FILE"
  local status=$?
  shelia::test::assert_eq 1 "$status" "init returns 1 when file doesn't exist"
  [[ -d "$TEST_TEMP_DIR" ]] || shelia::test::fail "init didn't create directory"
}

test_create() {
  declare -A params=(["RUN_ID"]="test-run" ["USER"]="tester")
  declare -a phases=("ALPHA" "BETA" "GAMMA")

  shelia::checkpoint::create params phases

  [[ -f "$CHECKPOINT_FILE" ]] || shelia::test::fail "checkpoint file not created"
  shelia::test::assert_eq "test-run" "$(shelia::checkpoint::read_value "CHECKPOINT_RUN_ID")" "read RUN_ID"
  shelia::test::assert_eq "tester" "$(shelia::checkpoint::read_value "USER")" "read USER param"
  shelia::test::assert_eq "pending" "$(shelia::checkpoint::get_phase_status "ALPHA")" "ALPHA should be pending"
}

test_value_management() {
  shelia::checkpoint::write_value "TEST_KEY" "test_value"
  shelia::test::assert_eq "test_value" "$(shelia::checkpoint::read_value "TEST_KEY")" "write/read value"

  shelia::checkpoint::delete_value "TEST_KEY"
  shelia::test::assert_eq "" "$(shelia::checkpoint::read_value "TEST_KEY")" "delete value"
}

test_phase_status() {
  shelia::checkpoint::mark_in_progress "ALPHA"
  shelia::test::assert_eq "in_progress" "$(shelia::checkpoint::get_phase_status "ALPHA")" "mark in_progress"

  shelia::checkpoint::mark_completed "ALPHA"
  shelia::test::assert_eq "completed" "$(shelia::checkpoint::get_phase_status "ALPHA")" "mark completed"

  shelia::checkpoint::mark_failed "BETA" "reasons"
  shelia::test::assert_eq "failed" "$(shelia::checkpoint::get_phase_status "BETA")" "mark failed"
  shelia::test::assert_eq "reasons" "$(shelia::checkpoint::read_value "LAST_ERROR")" "verify error message"
}

test_queries() {
  declare -a phases=("p1" "p2" "p3")
  shelia::checkpoint::create_simple
  shelia::checkpoint::mark_pending "p1"
  shelia::checkpoint::mark_pending "p2"
  shelia::checkpoint::mark_pending "p3"

  shelia::test::assert_eq "p1" "$(shelia::checkpoint::get_next_phase phases)" "next phase should be p1"

  shelia::checkpoint::mark_completed "p1"
  shelia::test::assert_eq "p2" "$(shelia::checkpoint::get_next_phase phases)" "next phase should be p2"

  shelia::checkpoint::mark_completed "p2"
  shelia::checkpoint::mark_completed "p3"
  shelia::test::assert_eq "" "$(shelia::checkpoint::get_next_phase phases)" "all completed returns empty"

  if shelia::checkpoint::all_completed phases; then
    shelia::test::pass "all_completed works"
  else
    shelia::test::fail "all_completed failed"
  fi
}

test_run_phase() {
  shelia::checkpoint::create_simple
  shelia::checkpoint::mark_pending "EXEC"

  success_func() { return 0; }
  fail_func() { return 1; }

  shelia::checkpoint::run_phase "EXEC" success_func
  shelia::test::assert_eq "completed" "$(shelia::checkpoint::get_phase_status "EXEC")" "run_phase success"

  shelia::checkpoint::mark_pending "FAIL"
  shelia::checkpoint::run_phase "FAIL" fail_func || true
  shelia::test::assert_eq "failed" "$(shelia::checkpoint::get_phase_status "FAIL")" "run_phase failure"
}

test_resume_mock() {
  # Mock prompt_yes_no to return yes
  shelia::shell::prompt_yes_no() { return 0; }

  declare -a phases=("R1")
  shelia::checkpoint::create_simple
  shelia::checkpoint::mark_pending "R1"

  if shelia::checkpoint::prompt_resume phases; then
    shelia::test::pass "prompt_resume (mock yes) returned 0"
  else
    shelia::test::fail "prompt_resume (mock yes) failed"
  fi
}

shelia::test::run_test "initialization" test_init
shelia::test::run_test "creation" test_create
shelia::test::run_test "value management" test_value_management
shelia::test::run_test "phase status" test_phase_status
shelia::test::run_test "phase queries" test_queries
shelia::test::run_test "run_phase wrapper" test_run_phase
shelia::test::run_test "resume prompt (mocked)" test_resume_mock

if [[ "${SHELIA_TEST_FAILURES:-0}" -gt 0 ]]; then
  shelia::logging::error "${SHELIA_TEST_FAILURES} test(s) failed."
  exit 1
fi

shelia::logging::info "All checkpoint tests passed."
