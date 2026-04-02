# shellcheck shell=bash
# Log sink, formatting, and global ERR trap (SRP: observability).

[[ -n "${__SHELIA_LIB_LOGGING_LOADED:-}" ]] && return 0
__SHELIA_LIB_LOGGING_LOADED=1

# Version check: logging.sh requires Bash 3.0+
# shellcheck source=./bootstrap.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/bootstrap.sh"
shelia::bootstrap::require_bash_version "logging.sh" "$__SHELIA_BASH_LOGGING_MIN_MAJOR" "$__SHELIA_BASH_LOGGING_MIN_MINOR"

# shellcheck source=./color.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/color.sh"

# Allow sourcing without config (SHELIA_LOG_FILE is optional until config sets it).
: "${SHELIA_LOG_FILE:=}"

function shelia::logging::log() {
  local msg="$1"
  if [[ -t 1 ]]; then
    if [[ -f "$SHELIA_LOG_FILE" ]]; then
      echo -e "$msg" | tee -a "$SHELIA_LOG_FILE" >/dev/tty
    else
      echo -e "$msg" >/dev/tty
    fi
  else
    if [[ -f "$SHELIA_LOG_FILE" ]]; then
      echo -e "$msg" | tee -a "$SHELIA_LOG_FILE"
    else
      echo -e "$msg"
    fi
  fi
}

function shelia::logging::construct_backtrace() {
  local backtrace=""
  local i=1

  while [[ $i -lt ${#FUNCNAME[@]} ]]; do
    local func_name="${FUNCNAME[$i]}"
    local source_file="${BASH_SOURCE[$i]}"
    local line_number="${BASH_LINENO[$((i - 1))]}"

    if [[ "$func_name" != "shelia::logging::construct_backtrace" ]]; then
      if [[ -n "$backtrace" ]]; then
        backtrace+="\n"
      fi
      backtrace+="  at ${func_name} ($(basename "$source_file"):${line_number})"
    fi

    ((i++))
  done

  echo -e "$backtrace"
}

function shelia::logging::construct_log_kind_info() {
  local timestamp
  timestamp=$(date -u '+%Y-%m-%dT%H:%M:%SZ')
  local msg
  msg="${timestamp} - ${FUNCNAME[2]} - $(basename "${BASH_SOURCE[2]}"):${BASH_LINENO[1]}"
  echo "$msg"
}

function shelia::logging::debug() {
  local msg
  msg="$(shelia::color::debug "[DEBUG] $(shelia::logging::construct_log_kind_info) - $1")"
  shelia::logging::log "$msg"
}

function shelia::logging::info() {
  local msg
  msg="$(shelia::color::info "[INFO] $(shelia::logging::construct_log_kind_info): $1")"
  shelia::logging::log "$msg"
}

function shelia::logging::warn() {
  local msg
  msg="$(shelia::color::warning "[WARNING] $(shelia::logging::construct_log_kind_info): $1")"
  shelia::logging::log "$msg"
}

function shelia::logging::error() {
  local pwd
  pwd="$(pwd)"
  local msg
  msg="$(shelia::color::failure "[ERROR] $(shelia::logging::construct_log_kind_info): $1 \n CURRENT DIR: $pwd\n$(shelia::logging::construct_backtrace)")"
  shelia::logging::log "$msg"
}

function shelia::logging::banner() {
  echo
  echo "======================================================="
  echo "$1"
  echo "======================================================="
  echo
}

# shellcheck disable=SC2317
function error_handler() {
  local exit_code=$?
  local line_number=$1
  local script_name="${BASH_SOURCE[0]}"
  local command="$BASH_COMMAND"

  local error_message="ERROR: Command failed in ${script_name}:${line_number}. Exit code: ${exit_code}. Command: ${command}"

  shelia::logging::error "$error_message"
  exit "$exit_code"
}

trap 'error_handler $LINENO' ERR
