#!/usr/bin/env bash
# shellcheck shell=bash

set -u

# shellcheck source=../lib/logging.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/../lib/logging.sh"

# shellcheck source=../lib/test.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/../lib/test.sh"
shelia::test::init

shelia::logging::info "Color tests start"

source_color() {
  if ! declare -F shelia::shell::begin_module >/dev/null 2>&1; then
    shelia::shell::begin_module() { return 0; }
  fi
  # shellcheck source=../lib/color.sh
  source "${ROOT_DIR}/lib/color.sh"
  trap - ERR
  set +e
  set +u
  set +o pipefail
}

test_wrap() {
  source_color
  local output
  output="$(shelia::color::wrap "${SUCCESS_COLOR_TAG}" "ok")"
  shelia::test::assert_eq $'\e[32mok\e[0m' "$output" "wrap applies color and reset"
}

test_named_colors() {
  source_color
  shelia::test::assert_eq $'\e[32mok\e[0m' "$(shelia::color::success "ok")" "success"
  shelia::test::assert_eq $'\e[31mbad\e[0m' "$(shelia::color::failure "bad")" "failure"
  shelia::test::assert_eq $'\e[33mwarn\e[0m' "$(shelia::color::warning "warn")" "warning"
  shelia::test::assert_eq $'\e[36minfo\e[0m' "$(shelia::color::info "info")" "info"
  shelia::test::assert_eq $'\e[90mdbg\e[0m' "$(shelia::color::debug "dbg")" "debug"
}

test_basic_palette() {
  source_color
  shelia::test::assert_eq $'\e[30mblack\e[0m' "$(shelia::color::black "black")" "black"
  shelia::test::assert_eq $'\e[97mwhite\e[0m' "$(shelia::color::white "white")" "white"
  shelia::test::assert_eq $'\e[31mred\e[0m' "$(shelia::color::red "red")" "red"
  shelia::test::assert_eq $'\e[32mgreen\e[0m' "$(shelia::color::green "green")" "green"
  shelia::test::assert_eq $'\e[33myellow\e[0m' "$(shelia::color::yellow "yellow")" "yellow"
  shelia::test::assert_eq $'\e[34mblue\e[0m' "$(shelia::color::blue "blue")" "blue"
  shelia::test::assert_eq $'\e[35mmagenta\e[0m' "$(shelia::color::magenta "magenta")" "magenta"
  shelia::test::assert_eq $'\e[36mcyan\e[0m' "$(shelia::color::cyan "cyan")" "cyan"
  shelia::test::assert_eq $'\e[90mgray\e[0m' "$(shelia::color::gray "gray")" "gray"
}

test_styles() {
  source_color
  shelia::test::assert_eq $'\e[1mbold\e[0m' "$(shelia::color::bold "bold")" "bold"
  shelia::test::assert_eq $'\e[4munderline\e[0m' "$(shelia::color::underline "underline")" "underline"
  shelia::test::assert_eq $'\e[2mdim\e[0m' "$(shelia::color::dim "dim")" "dim"
}

shelia::test::run_test "wrap" test_wrap
shelia::test::run_test "named colors" test_named_colors
shelia::test::run_test "basic palette" test_basic_palette
shelia::test::run_test "styles" test_styles

if [[ "${SHELIA_TEST_FAILURES:-0}" -gt 0 ]]; then
  shelia::logging::error "%s test(s) failed." "${SHELIA_TEST_FAILURES}"
  exit 1
fi

shelia::logging::info "All tests passed."
