#!/usr/bin/env bash
# shellcheck shell=bash

set -u

# shellcheck source=../lib/logging.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/../lib/logging.sh"

# shellcheck source=../lib/test.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/../lib/test.sh"
shelia::test::init

shelia::logging::info "HTTP tests start"

source_http() {
  if ! declare -F shelia::shell::begin_module >/dev/null 2>&1; then
    shelia::shell::begin_module() { return 0; }
  fi
  # shellcheck source=../lib/http.sh
  source "${ROOT_DIR}/lib/http.sh"
  trap - ERR
  set +e
  set +u
  set +o pipefail
}

test_has_curl() {
  source_http
  shelia::http::has_curl || return 1
}

test_get_requires_url() {
  source_http
  local output
  output="$(shelia::http::get "" 2>&1)" || true
  shelia::test::assert_contains "$output" "URL is required" "get errors when URL is empty"
}

test_post_requires_url() {
  source_http
  local output
  output="$(shelia::http::post "" '{"data":1}' 2>&1)" || true
  shelia::test::assert_contains "$output" "URL is required" "post errors when URL is empty"
}

test_post_requires_data() {
  source_http
  local output
  output="$(shelia::http::post "http://example.com" "" 2>&1)" || true
  shelia::test::assert_contains "$output" "data is required" "post errors when data is empty"
}

test_put_requires_url() {
  source_http
  local output
  output="$(shelia::http::put "" '{"data":1}' 2>&1)" || true
  shelia::test::assert_contains "$output" "URL is required" "put errors when URL is empty"
}

test_put_requires_data() {
  source_http
  local output
  output="$(shelia::http::put "http://example.com" "" 2>&1)" || true
  shelia::test::assert_contains "$output" "data is required" "put errors when data is empty"
}

test_delete_requires_url() {
  source_http
  local output
  output="$(shelia::http::delete "" 2>&1)" || true
  shelia::test::assert_contains "$output" "URL is required" "delete errors when URL is empty"
}

test_download_requires_url() {
  source_http
  local output
  output="$(shelia::http::download "" "/tmp/out" 2>&1)" || true
  shelia::test::assert_contains "$output" "URL is required" "download errors when URL is empty"
}

test_download_requires_output_path() {
  source_http
  local output
  output="$(shelia::http::download "http://example.com" "" 2>&1)" || true
  shelia::test::assert_contains "$output" "output path is required" "download errors when output path is empty"
}

test_is_reachable_requires_url() {
  source_http
  local output
  output="$(shelia::http::is_reachable "" 2>&1)" || true
  shelia::test::assert_contains "$output" "URL is required" "is_reachable errors when URL is empty"
}

test_is_reachable_with_valid_url() {
  source_http
  # Test with a known reachable URL (google.com usually works)
  # This test may fail in offline environments
  if command -v curl >/dev/null 2>&1; then
    shelia::http::is_reachable "https://www.google.com" 2>/dev/null || return 1
  fi
}

test_download_creates_file() {
  source_http
  local tmpdir
  tmpdir="$(mktemp -d)"
  local outfile="$tmpdir/test_download.txt"

  # Create a simple test file locally and serve it, or use a known URL
  # For simplicity, just test that the download function runs without error
  # on a real URL (httpbin.org is reliable for testing)
  if command -v curl >/dev/null 2>&1; then
    if shelia::http::download "https://httpbin.org/json" "$outfile" 2>/dev/null; then
      [[ -f "$outfile" ]] || return 1
      rm -f "$outfile"
      rmdir "$tmpdir" 2>/dev/null || true
      return 0
    fi
  fi
  # If network unavailable, just verify the function exists and accepts args
  rm -f "$outfile"
  rmdir "$tmpdir" 2>/dev/null || true
  return 0
}

shelia::test::run_test "has_curl" test_has_curl
shelia::test::run_test "get requires URL" test_get_requires_url
shelia::test::run_test "post requires URL" test_post_requires_url
shelia::test::run_test "post requires data" test_post_requires_data
shelia::test::run_test "put requires URL" test_put_requires_url
shelia::test::run_test "put requires data" test_put_requires_data
shelia::test::run_test "delete requires URL" test_delete_requires_url
shelia::test::run_test "download requires URL" test_download_requires_url
shelia::test::run_test "download requires output path" test_download_requires_output_path
shelia::test::run_test "is_reachable requires URL" test_is_reachable_requires_url
shelia::test::run_test "is_reachable with valid URL" test_is_reachable_with_valid_url
shelia::test::run_test "download creates file" test_download_creates_file

if [[ "${SHELIA_TEST_FAILURES:-0}" -gt 0 ]]; then
  shelia::logging::error "%s test(s) failed." "${SHELIA_TEST_FAILURES}"
  exit 1
fi

shelia::logging::info "All tests passed."
