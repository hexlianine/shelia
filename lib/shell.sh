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

# Detects whether the current shell is Bash.
# Behavior:
#   - Returns success (exit 0) when BASH_VERSION is set.
#   - Returns failure (exit 1) otherwise.
#
# Usage:
#   if shelia::shell::is_bash; then
#     ...
#   fi
function shelia::shell::is_bash() {
  [[ -n "${BASH_VERSION:-}" ]]
}

# Prints a function name from the Bash call stack (FUNCNAME).
# Details:
#   - Index defaults to 1 (the caller of the function that invoked this helper).
#   - Use 0 for the current function; larger indexes walk further up the stack.
#
# Usage:
#   printf '%s: error\n' "$(shelia::shell::function_name)" >&2
#
# Example:
#   # From inside foo, shelia::shell::function_name 1 prints the name of foo's caller.
function shelia::shell::function_name() {
  local index="${1:-1}"
  printf '%s' "${FUNCNAME[$index]:-}"
}

# Idempotent guard for sourcing a lib submodule: sets __SHELIA_LIB_<ID>_LOADED the first time only.
# Rules:
#   - Module id must be non-empty and use only A-Z, 0-9, and underscore.
#   - Returns 0 the first time the module is registered; returns 1 if it was already loaded.
#   - On duplicate load, callers typically follow with `return 0` to skip re-execution.
#   - Returns 1 and prints to stderr if the module id is missing or invalid.
#
# Usage:
#   # shellcheck source=./other.sh
#   source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/other.sh"
#   shelia::shell::begin_module OTHER || return 0
#
# Example:
#   shelia::shell::begin_module CONFIG || return 0
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

# Verifies that the script is running under Bash 4.3 or newer.
# On failure:
#   - Exits via shelia::logging::error if BASH_VERSION is unset (not Bash).
#   - Exits if the major/minor version is below 4.3.
#
# Usage:
#   shelia::shell::check_bash_version
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

# Ensures each named executable exists on PATH before proceeding.
# Behavior:
#   - Logs via shelia::logging::error for each missing command and returns 1 after checking all commands.
#   - Returns 0 when every command is available.
#
# Usage:
#   shelia::shell::check_requirements git curl jq || exit 1
#
# Example:
#   shelia::shell::check_requirements sed awk
function shelia::shell::check_requirements() {
  local required_commands=("$@")
  local missing=0

  for cmd in "${required_commands[@]}"; do
    if ! command -v "$cmd" &>/dev/null; then
      shelia::logging::error "Required command '$cmd' is not installed or not available in PATH. " \
        "Please install it and try again."
      missing=1
    fi
  done
  if [[ $missing -ne 0 ]]; then
    return 1
  fi
  return 0
}

# Runs a command string with eval, prints stdout/stderr to the terminal, and appends the same stream to a log file.
# Arguments and return:
#   - Arguments: (1) command string, (2) log file path, (3) error summary message, (4) success message.
#   - Creates the log file's parent directory when possible (mkdir -p, failures ignored).
#   - Returns 0 only if both the evaluated command and tee succeed; otherwise logs errors and returns 1.
#
# Usage:
#   shelia::shell::execute_command "$cmd" "/path/to/run.log" "Step failed" "Step completed"
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

# Strips leading and trailing whitespace from each argument.
# Details:
#   - Uses sed with [[:space:]] so spaces, tabs, and line breaks at the ends are removed.
#   - Prints all trimmed values as one space-separated line (same word-splitting pattern as echo "${array[@]}").
#
# Usage:
#   out=$(shelia::shell::trim_whitespaces "$a" "$b")
#
# Example:
#   shelia::shell::trim_whitespaces "  hello " $'  world\t'
#   # Output: hello world
function shelia::shell::trim_whitespaces() {
  local result=()
  for value in "$@"; do
    result+=("$(echo "$value" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')")
  done
  echo "${result[@]}"
}

# Escapes special characters in a string for safe use as the replacement part in a sed 's|pattern|REPLACEMENT|g' command.
# It escapes:
#   - backslashes (\) -> \\
#   - ampersands (&)  -> \&
#   - pipe characters (|) -> \| (the default delimiter used in this project's sed expressions)
#
# Usage:
#   repl_val=$(shelia::shell::escape_sed_replacement "$unsafe_string")
#   sed -e "s|pattern|$repl_val|g"
#
# Example:
#   input="refs/heads/feature|bug&fix"
#   safe=$(shelia::shell::escape_sed_replacement "$input")
#   # Output: refs/heads/feature\|bug\&fix
function shelia::shell::escape_sed_replacement() {
  printf '%s' "$1" | sed -e 's/\\/\\\\/g' -e 's/&/\\&/g' -e 's/|/\\|/g'
}

# Invokes another shell function by name and interprets its stdout.
# Behavior:
#   - If stdout is a signed integer string, that value becomes the exit status (return).
#   - Otherwise stdout is echoed so the caller can capture it with command substitution.
#
# Usage:
#   out=$(shelia::shell::decorator::enter_function my_func arg1 arg2)
#
# Example:
#   # If my_func prints "42", this returns exit code 42 with no stdout.
#   # If my_func prints "ok", this echoes "ok".
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

# Prompts on the terminal for yes or no, with an optional default when the user sends an empty line.
# Arguments and return:
#   - First argument: prompt text (default "Continue?").
#   - Second argument: default answer "y" or "n" (default "n"); controls [Y/n] versus [y/N].
#   - Returns 0 for yes, 1 for no. Prefers /dev/tty for input when stdin is not a TTY.
#
# Usage:
#   if shelia::shell::prompt_yes_no "Overwrite?" n; then
#     ...
#   fi
#
# Example:
#   shelia::shell::prompt_yes_no "Continue?" y
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
