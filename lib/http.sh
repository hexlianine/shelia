# shellcheck shell=bash
# HTTP client utilities for making HTTP requests (SRP: HTTP operations).

# shellcheck source=./shell.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/shell.sh"

# Version check: http.sh requires Bash 3.0+ (inherits shell.sh dependency)
shelia::bootstrap::require_bash_version "http.sh" "$__SHELIA_BASH_HTTP_MIN_MAJOR" "$__SHELIA_BASH_HTTP_MIN_MINOR"
shelia::shell::begin_module HTTP || return 0

# shellcheck source=./logging.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/logging.sh"

# Performs an HTTP GET request to the specified URL.
# Arguments:
#   - First argument: URL to request.
#   - Second argument (optional): Additional curl options (e.g., "--header 'Authorization: Bearer token'").
#   - Returns: Outputs response body on success; returns 1 on failure.
#
# Usage:
#   response=$(shelia::http::get "https://api.example.com/data")
#   response=$(shelia::http::get "https://api.example.com/data" "--header 'Authorization: Bearer xyz'")
function shelia::http::get() {
  local url="$1"
  local extra_opts="${2:-}"

  if [[ -z "$url" ]]; then
    shelia::logging::error "shelia::http::get: URL is required"
    return 1
  fi

  shelia::logging::debug "HTTP GET: $url"

  local curl_cmd="curl -sS -X GET"
  if [[ -n "$extra_opts" ]]; then
    curl_cmd="$curl_cmd $extra_opts"
  fi
  curl_cmd="$curl_cmd '$url'"

  shelia::shell::execute_command "$curl_cmd" "/tmp/shelia_http_$$.log" "HTTP GET failed" "HTTP GET completed" || return 1
}

# Performs an HTTP POST request to the specified URL.
# Arguments:
#   - First argument: URL to request.
#   - Second argument: Request body (JSON string or data).
#   - Third argument (optional): Content-Type header (default: "application/json").
#   - Fourth argument (optional): Additional curl options.
#   - Returns: Outputs response body on success; returns 1 on failure.
#
# Usage:
#   response=$(shelia::http::post "https://api.example.com/users" '{"name":"John"}')
#   response=$(shelia::http::post "https://api.example.com/data" "key=value" "application/x-www-form-urlencoded")
function shelia::http::post() {
  local url="$1"
  local data="$2"
  local content_type="${3:-application/json}"
  local extra_opts="${4:-}"

  if [[ -z "$url" ]]; then
    shelia::logging::error "shelia::http::post: URL is required"
    return 1
  fi
  if [[ -z "$data" ]]; then
    shelia::logging::error "shelia::http::post: data is required"
    return 1
  fi

  shelia::logging::debug "HTTP POST: $url"

  local curl_cmd="curl -sS -X POST"
  curl_cmd="$curl_cmd -H 'Content-Type: $content_type'"
  if [[ -n "$extra_opts" ]]; then
    curl_cmd="$curl_cmd $extra_opts"
  fi
  curl_cmd="$curl_cmd -d '$data' '$url'"

  shelia::shell::execute_command "$curl_cmd" "/tmp/shelia_http_$$.log" "HTTP POST failed" "HTTP POST completed" || return 1
}

# Performs an HTTP PUT request to the specified URL.
# Arguments:
#   - First argument: URL to request.
#   - Second argument: Request body (JSON string or data).
#   - Third argument (optional): Content-Type header (default: "application/json").
#   - Fourth argument (optional): Additional curl options.
#   - Returns: Outputs response body on success; returns 1 on failure.
#
# Usage:
#   response=$(shelia::http::put "https://api.example.com/users/123" '{"name":"Jane"}')
function shelia::http::put() {
  local url="$1"
  local data="$2"
  local content_type="${3:-application/json}"
  local extra_opts="${4:-}"

  if [[ -z "$url" ]]; then
    shelia::logging::error "shelia::http::put: URL is required"
    return 1
  fi
  if [[ -z "$data" ]]; then
    shelia::logging::error "shelia::http::put: data is required"
    return 1
  fi

  shelia::logging::debug "HTTP PUT: $url"

  local curl_cmd="curl -sS -X PUT"
  curl_cmd="$curl_cmd -H 'Content-Type: $content_type'"
  if [[ -n "$extra_opts" ]]; then
    curl_cmd="$curl_cmd $extra_opts"
  fi
  curl_cmd="$curl_cmd -d '$data' '$url'"

  shelia::shell::execute_command "$curl_cmd" "/tmp/shelia_http_$$.log" "HTTP PUT failed" "HTTP PUT completed" || return 1
}

# Performs an HTTP DELETE request to the specified URL.
# Arguments:
#   - First argument: URL to request.
#   - Second argument (optional): Additional curl options.
#   - Returns: Outputs response body on success; returns 1 on failure.
#
# Usage:
#   response=$(shelia::http::delete "https://api.example.com/users/123")
function shelia::http::delete() {
  local url="$1"
  local extra_opts="${2:-}"

  if [[ -z "$url" ]]; then
    shelia::logging::error "shelia::http::delete: URL is required"
    return 1
  fi

  shelia::logging::debug "HTTP DELETE: $url"

  local curl_cmd="curl -sS -X DELETE"
  if [[ -n "$extra_opts" ]]; then
    curl_cmd="$curl_cmd $extra_opts"
  fi
  curl_cmd="$curl_cmd '$url'"

  shelia::shell::execute_command "$curl_cmd" "/tmp/shelia_http_$$.log" "HTTP DELETE failed" "HTTP DELETE completed" || return 1
}

# Checks whether a URL is reachable (HTTP status 2xx).
# Arguments:
#   - First argument: URL to check.
#   - Returns: 0 if reachable (status 2xx), 1 otherwise.
#
# Usage:
#   if shelia::http::is_reachable "https://api.example.com"; then
#     ...
#   fi
function shelia::http::is_reachable() {
  local url="$1"

  if [[ -z "$url" ]]; then
    shelia::logging::error "shelia::http::is_reachable: URL is required"
    return 1
  fi

  shelia::logging::debug "Checking reachability: $url"

  local http_code
  http_code=$(curl -sS -o /dev/null -w "%{http_code}" --connect-timeout 5 "$url" 2>/dev/null) || http_code="000"

  case "$http_code" in
  2*)
    shelia::logging::debug "URL is reachable (HTTP $http_code)"
    return 0
    ;;
  *)
    shelia::logging::debug "URL not reachable (HTTP $http_code)"
    return 1
    ;;
  esac
}

# Downloads a file from a URL to a local path.
# Arguments:
#   - First argument: URL to download from.
#   - Second argument: Local file path to save to.
#   - Third argument (optional): Additional curl options.
#   - Returns: 0 on success, 1 on failure.
#
# Usage:
#   shelia::http::download "https://example.com/file.tar.gz" "/tmp/file.tar.gz"
function shelia::http::download() {
  local url="$1"
  local output_path="$2"
  local extra_opts="${3:-}"

  if [[ -z "$url" ]]; then
    shelia::logging::error "shelia::http::download: URL is required"
    return 1
  fi
  if [[ -z "$output_path" ]]; then
    shelia::logging::error "shelia::http::download: output path is required"
    return 1
  fi

  shelia::logging::debug "Downloading: $url -> $output_path"

  mkdir -p "$(dirname "$output_path")" 2>/dev/null || true

  local curl_cmd="curl -sS -L -o '$output_path'"
  if [[ -n "$extra_opts" ]]; then
    curl_cmd="$curl_cmd $extra_opts"
  fi
  curl_cmd="$curl_cmd '$url'"

  shelia::shell::execute_command "$curl_cmd" "/tmp/shelia_http_$$.log" "Download failed" "Download completed" || return 1
}

# Checks if curl is available on the system.
# Returns: 0 if curl is available, 1 otherwise.
#
# Usage:
#   if shelia::http::has_curl; then
#     ...
#   fi
function shelia::http::has_curl() {
  command -v curl &>/dev/null
}
