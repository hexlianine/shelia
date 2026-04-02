# shellcheck shell=bash
# Bash version detection and compliant-shell re-execution utilities.
#
# This module is intentionally dependency-free so it can be sourced before
# any other shelia library — including when running under an old system Bash.

[[ -n "${__SHELIA_LIB_BOOTSTRAP_LOADED:-}" ]] && return 0
__SHELIA_LIB_BOOTSTRAP_LOADED=1

# Minimum Bash version required by the project (global default).
readonly __SHELIA_BASH_MIN_MAJOR=4
readonly __SHELIA_BASH_MIN_MINOR=3

# Module-specific minimum Bash versions.
# checkpoint.sh requires Bash 4.3+ for local -n (nameref) feature.
readonly __SHELIA_BASH_CHECKPOINT_MIN_MAJOR=4
readonly __SHELIA_BASH_CHECKPOINT_MIN_MINOR=3

# shell.sh requires Bash 4.0+ for printf -v and set -E.
readonly __SHELIA_BASH_SHELL_MIN_MAJOR=4
readonly __SHELIA_BASH_SHELL_MIN_MINOR=0

# logging.sh, color.sh, git.sh, maven.sh, test.sh, workspace.sh - Bash 3.x compatible.
readonly __SHELIA_BASH_LOGGING_MIN_MAJOR=3
readonly __SHELIA_BASH_LOGGING_MIN_MINOR=0

readonly __SHELIA_BASH_COLOR_MIN_MAJOR=3
readonly __SHELIA_BASH_COLOR_MIN_MINOR=0

readonly __SHELIA_BASH_GIT_MIN_MAJOR=3
readonly __SHELIA_BASH_GIT_MIN_MINOR=0

readonly __SHELIA_BASH_MAVEN_MIN_MAJOR=3
readonly __SHELIA_BASH_MAVEN_MIN_MINOR=0

readonly __SHELIA_BASH_TEST_MIN_MAJOR=3
readonly __SHELIA_BASH_TEST_MIN_MINOR=0

readonly __SHELIA_BASH_WORKSPACE_MIN_MAJOR=3
readonly __SHELIA_BASH_WORKSPACE_MIN_MINOR=0

# Checks if the current Bash version meets the specified minimum requirements.
# @param $1 required_major - Minimum major version required.
# @param $2 required_minor - Minimum minor version required.
# @return 0 if current Bash meets requirements, 1 otherwise.
#
# Usage:
#   if shelia::bootstrap::check_bash_version 4 3; then
#     echo "Bash version OK"
#   fi
function shelia::bootstrap::check_bash_version() {
  local required_major="$1"
  local required_minor="$2"

  local current_major="${BASH_VERSINFO[0]:-0}"
  local current_minor="${BASH_VERSINFO[1]:-0}"

  if [[ "$current_major" -gt "$required_major" ]] ||
    { [[ "$current_major" -eq "$required_major" ]] &&
      [[ "$current_minor" -ge "$required_minor" ]]; }; then
    return 0
  fi
  return 1
}

# Checks if the current Bash version meets requirements and exits with an error if not.
# @param $1 module_name - Name of the module requiring the check.
# @param $2 required_major - Minimum major version required.
# @param $3 required_minor - Minimum minor version required.
# @return 0 if current Bash meets requirements, exits 1 otherwise.
#
# Usage:
#   shelia::bootstrap::require_bash_version "checkpoint" 4 3
function shelia::bootstrap::require_bash_version() {
  local module_name="$1"
  local required_major="$2"
  local required_minor="$3"

  if ! shelia::bootstrap::check_bash_version "$required_major" "$required_minor"; then
    printf 'ERROR: %s module requires Bash %d.%d or later (running %s).\n' \
      "$module_name" "$required_major" "$required_minor" "${BASH_VERSION:-unknown}" >&2
    printf 'Install a modern Bash and retry, e.g.:\n  brew install bash\n' >&2
    exit 1
  fi
}

# Searches well-known installation paths for a Bash binary that satisfies the
# minimum version requirement, then prints its resolved path.
# Candidates are checked in order:
#   /opt/homebrew/bin/bash      – Apple Silicon Homebrew
#   /usr/local/bin/bash         – Intel Mac Homebrew
#   /home/linuxbrew/.linuxbrew/bin/bash – Linux Homebrew
#   /bin/bash                   – Linux standard location
#   /usr/bin/bash               – Linux alternative location
#   /usr/local/bin/bash         – Linux source compile location
#   bash                        – first match on PATH
#
# Returns 0 and prints the path on success.
# Returns 1 and prints nothing when no qualifying binary is found.
#
# Usage:
#   compliant=$(shelia::bootstrap::find_compliant) || exit 1
function shelia::bootstrap::find_compliant() {
  local candidates=(
    /opt/homebrew/bin/bash
    /usr/local/bin/bash
    /home/linuxbrew/.linuxbrew/bin/bash
    /bin/bash
    /usr/bin/bash
    bash
  )
  local candidate resolved major minor
  for candidate in "${candidates[@]}"; do
    resolved=$(command -v "$candidate" 2>/dev/null) || continue
    major=$("$resolved" -c 'echo "${BASH_VERSINFO[0]}"' 2>/dev/null) || continue
    minor=$("$resolved" -c 'echo "${BASH_VERSINFO[1]}"' 2>/dev/null) || continue
    if [[ "$major" -gt "$__SHELIA_BASH_MIN_MAJOR" ]] ||
      { [[ "$major" -eq "$__SHELIA_BASH_MIN_MAJOR" ]] &&
        [[ "$minor" -ge "$__SHELIA_BASH_MIN_MINOR" ]]; }; then
      printf '%s' "$resolved"
      return 0
    fi
  done
  return 1
}

# Re-executes the calling script under a compliant Bash when the running shell
# is too old.  If the current Bash already meets the minimum version, returns
# immediately (no-op).  When a re-exec is needed but no qualifying Bash is
# found, exits 1 with a diagnostic message pointing to the install step.
#
# NOTE: This function calls exec, which replaces the current process.
#       Call it from the top-level script, never from a subshell or pipe.
#
# Arguments:
#   $1  – path of the script being executed (pass ${BASH_SOURCE[0]} or $0)
#   $@  – remaining arguments, forwarded verbatim to the re-executed script
#
# Usage:
#   # At the top of your entry-point script, before sourcing other libs:
#   # shellcheck source=./lib/bootstrap.sh
#   source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib/bootstrap.sh"
#   shelia::bootstrap::ensure "${BASH_SOURCE[0]}" "$@"
function shelia::bootstrap::ensure() {
  local script="$1"
  shift

  local major="${BASH_VERSINFO[0]:-0}"
  local minor="${BASH_VERSINFO[1]:-0}"

  # Already running a compliant Bash — nothing to do.
  if [[ "$major" -gt "$__SHELIA_BASH_MIN_MAJOR" ]] ||
    { [[ "$major" -eq "$__SHELIA_BASH_MIN_MAJOR" ]] &&
      [[ "$minor" -ge "$__SHELIA_BASH_MIN_MINOR" ]]; }; then
    return 0
  fi

  local compliant_bash
  if ! compliant_bash=$(shelia::bootstrap::find_compliant); then
    printf 'ERROR: Bash %d.%d or later is required (running %s).\n' \
      "$__SHELIA_BASH_MIN_MAJOR" "$__SHELIA_BASH_MIN_MINOR" "${BASH_VERSION:-unknown}" >&2
    printf 'Install a modern Bash and retry, e.g.:\n  brew install bash\n' >&2
    exit 1
  fi

  exec "$compliant_bash" -- "$script" "$@"
}
