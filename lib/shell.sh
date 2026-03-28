# shellcheck shell=bash
# Host prerequisites, command execution, and interactive helpers (SRP: shell UX).

[[ -n "${__SHELIA_LIB_SHELL_LOADED:-}" ]] && return 0
__SHELIA_LIB_SHELL_LOADED=1

set -e
set -u
set -o pipefail
set -E

# shellcheck source=./logging.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/logging.sh"

function shelia::shell::is_bash() {
  [[ -n "${BASH_VERSION:-}" ]]
}

function shelia::shell::function_name() {
  local index="${1:-1}"
  printf '%s' "${FUNCNAME[$index]:-}"
}

# Idempotent lib module load (sets _SHELIA_LIB_<ID>_LOADED). Call after sourcing this file:
#   shelia::shell::begin_module CONFIG || return 0
# Returns 1 if the module was already loaded (caller should `return 0`).
function shelia::shell::begin_module() {
  local mid="$1"
  if [[ -z "$mid" ]]; then
    printf '%s: Missing module id argument\n' "$(shelia::shell::function_name)" >&2
    return 1
  fi
  case "$mid" in
    '' | *[!A-Z0-9_]*)
      printf '%s: invalid module id %q\n' "$(shelia::shell::function_name)" "$mid" >&2
      return 1
      ;;
  esac
  local varname="__SHELIA_LIB_${mid}_LOADED"
  if [[ -n "${!varname:-}" ]]; then
    return 1
  fi
  printf -v "$varname" '%s' 1
  return 0
}

function shelia::shell::check_bash_version() {
  local required_smallest_version="4.3"

  if [ -z "${BASH_VERSION:-}" ]; then
    shelia::logging::error "This script requires Bash shell to run. Please execute it with bash."
    exit 1
  fi

  if [[ "${BASH_VERSINFO[0]}" -lt "${required_smallest_version%%.*}" ]] ||
    { [[ "${BASH_VERSINFO[0]}" -eq "${required_smallest_version%%.*}" ]] &&
      [[ "${BASH_VERSINFO[1]}" -lt "${required_smallest_version##*.}" ]]; }; then
    shelia::logging::error "This script requires Bash version $required_smallest_version or later. " \
      "Current version: ${BASH_VERSION}."
    exit 1
  fi
}

function shelia::shell::check_requirements() {
  local required_commands=("$@")

  for cmd in "${required_commands[@]}"; do
    if ! command -v "$cmd" &>/dev/null; then
      shelia::logging::error "Required command '$cmd' is not installed or not available in PATH. " \
        "Please install it and try again."
      return 1
    fi
  done
  return 0
}

function shelia::shell::execute_command() {
  local command="$1"
  local SHELIA_LOG_FILE="$2"
  local error_msg="$3"
  local success_msg="$4"
  local pipe_stat
  local cmd_status tee_status

  mkdir -p "$(dirname "$SHELIA_LOG_FILE")" 2>/dev/null || true

  set +e
  eval "$command" 2>&1 | tee -a "$SHELIA_LOG_FILE"
  pipe_stat=("${PIPESTATUS[@]}")
  set -e

  cmd_status="${pipe_stat[0]:-1}"
  tee_status="${pipe_stat[1]:-0}"

  if [[ "$cmd_status" -eq 0 && "$tee_status" -eq 0 ]]; then
    shelia::logging::info "$success_msg"
    return 0
  fi

  if [[ "$tee_status" -ne 0 ]]; then
    shelia::logging::error "$error_msg (tee append failed, exit $tee_status): $SHELIA_LOG_FILE"
  else
    shelia::logging::error "$error_msg (command exit $cmd_status)"
  fi
  shelia::logging::error "Check the log file for details: $SHELIA_LOG_FILE"
  return 1
}

function shelia::shell::trim_whitespaces() {
  local result=()
  for value in "$@"; do
    result+=("$(echo "$value" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')")
  done
  echo "${result[@]}"
}

function shelia::shell::decorator::enter_function() {
  local function_name="$1"
  shift 1

  local result
  result=$("$function_name" "$@")
  if [[ "$result" =~ ^-?[0-9]+$ ]]; then
    return "$result"
  else
    echo "$result"
  fi
}

function shelia::shell::prompt_yes_no() {
  local prompt="${1:-Continue?}"
  local default="${2:-n}"
  local response
  local prompt_suffix

  if [[ "${default,,}" == "y" ]]; then
    prompt_suffix="[Y/n]"
  else
    prompt_suffix="[y/N]"
  fi

  while true; do
    local prompt_text
    prompt_text="$(shelia::color::info "${prompt} ${prompt_suffix}: ")"
    if [[ -w /dev/tty ]] 2>/dev/null; then
      echo -en "${prompt_text}" >/dev/tty
    else
      echo -en "${prompt_text}"
    fi

    if [[ -t 0 ]]; then
      read -r response
    elif [[ -r /dev/tty ]] 2>/dev/null; then
      read -r response </dev/tty
    else
      read -r response
    fi

    if [[ -z "$response" ]]; then
      response="$default"
    fi

    case "${response,,}" in
      y|yes)
        return 0
        ;;
      n|no)
        return 1
        ;;
      *)
        if [[ -w /dev/tty ]] 2>/dev/null; then
          echo "Please answer 'y' or 'n'." >/dev/tty
        else
          echo "Please answer 'y' or 'n'."
        fi
        ;;
    esac
  done
}
