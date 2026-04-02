# shellcheck shell=bash
# Working tree layout for batch upgrades (SRP: workspace lifecycle).

# shellcheck source=./shell.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/shell.sh"

# Version check: workspace.sh requires Bash 3.0+ (inherits shell.sh dependency)
shelia::bootstrap::require_bash_version "workspace.sh" "$__SHELIA_BASH_WORKSPACE_MIN_MAJOR" "$__SHELIA_BASH_WORKSPACE_MIN_MINOR"
shelia::shell::begin_module WORKSPACE || return 0
# shellcheck source=./git.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/git.sh"

function shelia::workspace::resolve_workspace_paths() {
  local fields=(SHELIA_WORKING_DIR SHELIA_CONFIG_DIR SHELIA_LOG_DIR)
  local name value resolved

  for name in "${fields[@]}"; do
    value="${!name:-}"
    if [[ -z "$value" ]]; then
      continue
    fi

    resolved="$value"
    if [[ "$resolved" == "~"* ]]; then
      resolved="${resolved/#\~/$HOME}"
    fi

    if [[ "$resolved" == *'$('* || "$resolved" == *'`'* ]]; then
      shelia::logging::error "${name} contains unsupported command substitution: $value"
      exit 1
    fi

    if [[ "$resolved" == *'$'* ]]; then
      resolved="$(eval "printf '%s' \"$resolved\"")"
    fi

    printf -v "$name" '%s' "$resolved"
  done

  if [[ -n "${SPRINT:-}" ]]; then
    local sprint_resolved="$SPRINT"
    if [[ "$sprint_resolved" == *'$('* || "$sprint_resolved" == *'`'* ]]; then
      shelia::logging::error "SPRINT contains unsupported command substitution: $SPRINT"
      exit 1
    fi
    if [[ "$sprint_resolved" == *'$'* ]]; then
      sprint_resolved="$(eval "printf '%s' \"$sprint_resolved\"")"
    fi
    SPRINT="$sprint_resolved"
  fi
}

function shelia::workspace::setup_log_directory() {
  local log_dir="$1"
  local prefix="$2"
  local timestamp
  timestamp=$(date '+%Y%m%d_%H%M%S')

  mkdir -p "${log_dir}"
  echo "${log_dir}/${prefix}_${timestamp}.log"
}

function shelia::workspace::setup_working_directory() {
  shelia::logging::banner "Creating working directory for version upgrade process"

  shelia::workspace::resolve_workspace_paths

  mkdir -p "${SHELIA_WORKING_DIR}/${SHELIA_CONFIG_DIR}"
  mkdir -p "${SHELIA_WORKING_DIR}/${SHELIA_LOG_DIR}"
  shelia::logging::info "Working directory setup completed"

  if [[ "$(pwd)" != "$SHELIA_WORKING_DIR" ]]; then
    if shelia::shell::prompt_yes_no "Do you want to change to the directory: $SHELIA_WORKING_DIR?"; then
      cd "$SHELIA_WORKING_DIR" || exit 1
      shelia::logging::info "Changed directory to: $(pwd)"
    else
      exit 0
    fi
  fi
}
