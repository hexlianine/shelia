#!/bin/bash
#
# Checkpoint/Resume System for Long-Running Scripts
#
# Provides functionality to save and restore execution state,
# allowing scripts to resume from the last successful phase
# after an interruption.
#
# Version requirement: Bash 4.3+ (for local -n nameref feature)
#
# Usage:
#   source checkpoint.sh
#
# Process Flow:
#
#     [Start Script]
#           |
#           v
#    [shelia::checkpoint::init]
#           |
#           v
#    +-------------+       No        +--------------------+
#    | Checkpoint? +---------------->| shelia::checkpoint::create |
#    +------+------+                 +---------+----------+
#           |                                  |
#           | Yes                              |
#           v                                  |
#    +-------------+       Resume              |
#    |prompt_resume|<--------------------------+
#    +------+------+
#           |
#           | Fresh Start
#           v
#    +-------------+
#    |   cleanup   +---------------------------+
#    +-------------+                           |
#                                              v
#                                    +--------------------+
#               +--------------------+ Loop through PHASES| <---+
#               |                    +---------+----------+     |
#               v                              |                |
#        /-----------\        Yes              |                |
#       ( Completed?  ) <----------------------+                |
#        \-----------/                                          |
#               |                                               |
#               | No                                            |
#               v                                               |
#    +---------------------+                                    |
#    |shelia::checkpoint::run_phase|                                    |
#    +----------+----------+                                    |
#               |                                               |
#               v                                               |
#    +---------------------+                                    |
#    |  Execute Function   |                                    |
#    +----------+----------+                                    |
#               |                                               |
#        /-----------\                                          |
#       (   Success?  )                                         |
#        \-----------/                                          |
#         |         |                                           |
#      Yes|         |No                                         |
#         v         v                                           |
#    +---------+ +---------+                                    |
#    |Mark Done| |Mark Fail|                                    |
#    +----+----+ +----+----+                                    |
#         |           |                                         |
#         v           v                                         |
#    (Next Phase)  [ STOP ]                                     |
#         |                                                     |
#         +-----------------------------------------------------+

#
# Required variables (must be set before using checkpoint functions):
#   - CHECKPOINT_FILE: Path to the checkpoint state file
#   - PHASES: Array of phase names in execution order
#
# Optional variables:
#   - LOG_DIR: Directory for checkpoint files (used by shelia::checkpoint::get_default_file_path)

# Source common functions if not already loaded
if ! type shelia::logging::info &>/dev/null; then
  SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  # shellcheck source=./logging.sh
  source "${SCRIPT_DIR}/logging.sh" 2>/dev/null || {
    echo -e "\e[31m Logging functions file not found. Please ensure logging.sh exists. \e[0m"
    exit 1
  }
fi

if ! type shelia::shell::prompt_yes_no &>/dev/null; then
  SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  # shellcheck source=./shell.sh
  source "${SCRIPT_DIR}/shell.sh" 2>/dev/null || {
    echo -e "\e[31m Shell functions file not found. Please ensure shell.sh exists. \e[0m"
    exit 1
  }
fi

# Version check: checkpoint.sh requires Bash 4.3+ (for local -n nameref feature)
# shellcheck source=./bootstrap.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/bootstrap.sh"
shelia::bootstrap::require_bash_version "checkpoint.sh" "$__SHELIA_BASH_CHECKPOINT_MIN_MAJOR" "$__SHELIA_BASH_CHECKPOINT_MIN_MINOR"

# ============================================================================
# Checkpoint State Management
# ============================================================================

function shelia::checkpoint::get_default_file_path() {
  local prefix="${1:-checkpoint}"
  local identifier="${2:-default}"
  echo "${LOG_DIR}/.${prefix}_${identifier}.checkpoint"
}

function shelia::checkpoint::init() {
  local checkpoint_file="${1:-$CHECKPOINT_FILE}"

  if [[ -z "$checkpoint_file" ]]; then
    shelia::logging::error "CHECKPOINT_FILE is not set"
    return 1
  fi

  CHECKPOINT_FILE="$checkpoint_file"

  local checkpoint_dir
  checkpoint_dir="$(dirname "$CHECKPOINT_FILE")"

  if [[ ! -d "$checkpoint_dir" ]]; then
    mkdir -p "$checkpoint_dir"
  fi

  if [[ -f "$CHECKPOINT_FILE" ]]; then
    shelia::logging::info "Checkpoint file found: $CHECKPOINT_FILE"
    return 0
  else
    shelia::logging::info "No existing checkpoint found. Starting fresh run."
    return 1
  fi
}

function shelia::checkpoint::exists() {
  [[ -f "$CHECKPOINT_FILE" ]]
}

function shelia::checkpoint::create() {
  local -n params_ref=$1
  local -n phases_ref=$2

  if [[ -z "$CHECKPOINT_FILE" ]]; then
    shelia::logging::error "CHECKPOINT_FILE is not set"
    return 1
  fi

  local run_id
  run_id="${params_ref[RUN_ID]:-$(date '+%Y%m%d_%H%M%S')}"

  {
    echo "# Checkpoint State File"
    echo "# Generated: $(date -u '+%Y-%m-%dT%H:%M:%SZ')"
    echo "CHECKPOINT_RUN_ID=\"${run_id}\""

    for key in "${!params_ref[@]}"; do
      echo "${key}=\"${params_ref[$key]}\""
    done

    for phase in "${phases_ref[@]}"; do
      echo "PHASE_${phase^^}=pending"
    done
  } >"$CHECKPOINT_FILE"

  shelia::logging::info "Created new checkpoint: $CHECKPOINT_FILE"
}

function shelia::checkpoint::create_simple() {
  if [[ -z "$CHECKPOINT_FILE" ]]; then
    shelia::logging::error "CHECKPOINT_FILE is not set"
    return 1
  fi

  {
    echo "# Checkpoint State File"
    echo "# Generated: $(date -u '+%Y-%m-%dT%H:%M:%SZ')"
  } >"$CHECKPOINT_FILE"

  shelia::logging::info "Created new checkpoint: $CHECKPOINT_FILE"
}

function shelia::checkpoint::read_value() {
  local key=$1

  if [[ ! -f "$CHECKPOINT_FILE" ]]; then
    return 1
  fi

  grep "^${key}=" "$CHECKPOINT_FILE" 2>/dev/null | cut -d'=' -f2- | tr -d '"'
}

function shelia::checkpoint::write_value() {
  local key=$1
  local value=$2

  if [[ ! -f "$CHECKPOINT_FILE" ]]; then
    shelia::logging::error "Checkpoint file does not exist"
    return 1
  fi

  if grep -q "^${key}=" "$CHECKPOINT_FILE" 2>/dev/null; then
    sed "s|^${key}=.*|${key}=\"${value}\"|" "$CHECKPOINT_FILE" >"${CHECKPOINT_FILE}.tmp" && mv "${CHECKPOINT_FILE}.tmp" "$CHECKPOINT_FILE"
  else
    echo "${key}=\"${value}\"" >>"$CHECKPOINT_FILE"
  fi
}

function shelia::checkpoint::delete_value() {
  local key=$1

  if [[ ! -f "$CHECKPOINT_FILE" ]]; then
    return 1
  fi

  sed "/^${key}=/d" "$CHECKPOINT_FILE" >"${CHECKPOINT_FILE}.tmp" && mv "${CHECKPOINT_FILE}.tmp" "$CHECKPOINT_FILE"
}

# ============================================================================
# Phase Status Management
# ============================================================================

function shelia::checkpoint::get_phase_status() {
  local phase=$1
  local phase_key="PHASE_${phase^^}"

  shelia::checkpoint::read_value "$phase_key"
}

function shelia::checkpoint::is_completed() {
  local phase=$1
  local status
  status=$(shelia::checkpoint::get_phase_status "$phase")
  [[ "$status" == "completed" ]]
}

function shelia::checkpoint::is_in_progress() {
  local phase=$1
  local status
  status=$(shelia::checkpoint::get_phase_status "$phase")
  [[ "$status" == "in_progress" ]]
}

function shelia::checkpoint::is_pending() {
  local phase=$1
  local status
  status=$(shelia::checkpoint::get_phase_status "$phase")
  [[ "$status" == "pending" || -z "$status" ]]
}

function shelia::checkpoint::mark_pending() {
  local phase=$1
  local phase_key="PHASE_${phase^^}"

  shelia::checkpoint::write_value "$phase_key" "pending"
  shelia::checkpoint::write_value "LAST_UPDATED" "$(date -u '+%Y-%m-%dT%H:%M:%SZ')"

  shelia::logging::info "Phase '$phase' marked as pending"
}

function shelia::checkpoint::mark_in_progress() {
  local phase=$1
  local phase_key="PHASE_${phase^^}"

  shelia::checkpoint::write_value "$phase_key" "in_progress"
  shelia::checkpoint::write_value "LAST_UPDATED" "$(date -u '+%Y-%m-%dT%H:%M:%SZ')"

  shelia::logging::info "Phase '$phase' marked as in_progress"
}

function shelia::checkpoint::mark_completed() {
  local phase=$1
  local phase_key="PHASE_${phase^^}"

  shelia::checkpoint::write_value "$phase_key" "completed"
  shelia::checkpoint::write_value "LAST_UPDATED" "$(date -u '+%Y-%m-%dT%H:%M:%SZ')"

  shelia::logging::info "Phase '$phase' marked as completed"
}

function shelia::checkpoint::mark_failed() {
  local phase=$1
  local error_msg="${2:-}"
  local phase_key="PHASE_${phase^^}"

  shelia::checkpoint::write_value "$phase_key" "failed"
  shelia::checkpoint::write_value "LAST_UPDATED" "$(date -u '+%Y-%m-%dT%H:%M:%SZ')"
  if [[ -n "$error_msg" ]]; then
    shelia::checkpoint::write_value "LAST_ERROR" "$error_msg"
  fi

  shelia::logging::info "Phase '$phase' marked as failed"
}

# ============================================================================
# Phase Query Functions
# ============================================================================

function shelia::checkpoint::get_completed_phases() {
  local -n _gcp_phases_ref=$1
  local completed=()

  for phase in "${_gcp_phases_ref[@]}"; do
    if shelia::checkpoint::is_completed "$phase"; then
      completed+=("$phase")
    fi
  done

  echo "${completed[*]}"
}

function shelia::checkpoint::get_next_phase() {
  local -n _gnp_phases_ref=$1

  for phase in "${_gnp_phases_ref[@]}"; do
    if ! shelia::checkpoint::is_completed "$phase"; then
      echo "$phase"
      return 0
    fi
  done

  echo ""
}

function shelia::checkpoint::all_completed() {
  local -n _ac_phases_ref=$1

  for phase in "${_ac_phases_ref[@]}"; do
    if ! shelia::checkpoint::is_completed "$phase"; then
      return 1
    fi
  done
  return 0
}

function shelia::checkpoint::count_completed() {
  local -n _cc_phases_ref=$1
  local count=0

  for phase in "${_cc_phases_ref[@]}"; do
    if shelia::checkpoint::is_completed "$phase"; then
      ((count++))
    fi
  done

  echo "$count"
}

# ============================================================================
# Validation Functions
# ============================================================================

function shelia::checkpoint::validate_params() {
  local -n expected_params=$1
  local mismatch=false

  for key in "${!expected_params[@]}"; do
    local saved_value
    saved_value=$(shelia::checkpoint::read_value "$key")
    local expected_value="${expected_params[$key]}"

    if [[ "$saved_value" != "$expected_value" ]]; then
      shelia::logging::warn "Parameter mismatch for '$key':"
      shelia::logging::warn "  Saved:    $saved_value"
      shelia::logging::warn "  Expected: $expected_value"
      mismatch=true
    fi
  done

  if [[ "$mismatch" == true ]]; then
    return 1
  fi

  return 0
}

# ============================================================================
# Display Functions
# ============================================================================

function shelia::checkpoint::show_status() {
  local -n _ss_phases_ref=$1
  local title="${2:-Checkpoint Status}"

  local run_id last_updated
  run_id=$(shelia::checkpoint::read_value "CHECKPOINT_RUN_ID")
  last_updated=$(shelia::checkpoint::read_value "LAST_UPDATED")

  echo ""
  echo "======================================================="
  echo "[CHECKPOINT] $title"
  echo "======================================================="
  if [[ -n "$run_id" ]]; then
    echo "  Run ID: $run_id"
  fi
  if [[ -n "$last_updated" ]]; then
    echo "  Last Updated: $last_updated"
  fi
  echo ""
  echo "  Phase Status:"

  for phase in "${_ss_phases_ref[@]}"; do
    local status
    status=$(shelia::checkpoint::get_phase_status "$phase")
    local status_icon
    case "$status" in
    completed) status_icon="[DONE]" ;;
    in_progress) status_icon="[IN PROGRESS]" ;;
    pending) status_icon="[PENDING]" ;;
    failed) status_icon="[FAILED]" ;;
    *) status_icon="[UNKNOWN]" ;;
    esac
    echo "    $status_icon $phase"
  done

  local next_phase
  next_phase=$(shelia::checkpoint::get_next_phase _ss_phases_ref)
  if [[ -n "$next_phase" ]]; then
    echo ""
    echo "  Next phase: $next_phase"
  else
    echo ""
    echo "  All phases completed!"
  fi
  echo "======================================================="
  echo ""
}

# ============================================================================
# Interactive Functions
# ============================================================================

function shelia::checkpoint::prompt_resume() {
  local -n _pr_phases_ref=$1
  local title="${2:-Previous run detected}"

  shelia::checkpoint::show_status _pr_phases_ref "$title"

  local next_phase
  next_phase=$(shelia::checkpoint::get_next_phase _pr_phases_ref)

  if [[ -z "$next_phase" ]]; then
    shelia::logging::info "All phases already completed."
    return 0
  fi

  if shelia::shell::prompt_yes_no "Do you want to resume from '$next_phase'?"; then
    shelia::logging::info "Resuming from phase: $next_phase"
    return 0
  else
    if shelia::shell::prompt_yes_no "Do you want to discard the checkpoint and start fresh?"; then
      shelia::checkpoint::cleanup
      return 1
    else
      shelia::logging::info "Exiting without changes."
      exit 0
    fi
  fi
}

# ============================================================================
# Cleanup Functions
# ============================================================================

function shelia::checkpoint::cleanup() {
  if [[ -f "$CHECKPOINT_FILE" ]]; then
    rm -f "$CHECKPOINT_FILE"
    shelia::logging::info "Checkpoint file removed: $CHECKPOINT_FILE"
  fi
}

function shelia::checkpoint::reset_all_phases() {
  local -n _rap_phases_ref=$1

  for phase in "${_rap_phases_ref[@]}"; do
    shelia::checkpoint::mark_pending "$phase"
  done

  shelia::logging::info "All phases reset to pending"
}

# ============================================================================
# Phase Execution Wrapper
# ============================================================================

function shelia::checkpoint::run_phase() {
  local phase_name="$1"
  local phase_func="$2"
  shift 2

  if shelia::checkpoint::is_completed "$phase_name"; then
    shelia::logging::info "Skipping completed phase: $phase_name"
    return 0
  fi

  shelia::checkpoint::mark_in_progress "$phase_name"

  if "$phase_func" "$@"; then
    shelia::checkpoint::mark_completed "$phase_name"
    shelia::logging::info "Phase '$phase_name' completed successfully"
    return 0
  else
    shelia::checkpoint::mark_failed "$phase_name" "Phase function returned non-zero exit code"
    shelia::logging::error "Phase '$phase_name' failed"
    return 1
  fi
}

# ============================================================================
# Utility Functions
# ============================================================================

function shelia::checkpoint::get_file_path() {
  echo "$CHECKPOINT_FILE"
}

function shelia::checkpoint::dump() {
  if [[ -f "$CHECKPOINT_FILE" ]]; then
    shelia::logging::info "Checkpoint file contents:"
    cat "$CHECKPOINT_FILE"
  else
    shelia::logging::warn "No checkpoint file exists"
  fi
}
