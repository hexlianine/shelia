# shellcheck shell=bash
# Git workflows and branch policy (SRP: version-control operations).

# shellcheck source=./shell.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/shell.sh"

# Version check: git.sh requires Bash 3.0+ (inherits shell.sh dependency)
shelia::bootstrap::require_bash_version "git.sh" "$__SHELIA_BASH_GIT_MIN_MAJOR" "$__SHELIA_BASH_GIT_MIN_MINOR"
shelia::shell::begin_module GIT || return 0

# Example: Customizing git protections and remote configuration with shelia::git::init
#
# This code snippet demonstrates how to customize Git branch protection policies
# and remote provider settings for your workflow by invoking shelia::git::init
# with specific arguments. This allows you to control which branches are
# protected, whether protected branches can be created/deleted, and which remote
# is considered the primary provider.
#
# Each argument is a KEY=VALUE pair, for example:
# - SHELIA_GIT_PROTECTED_BRANCHES_REGEX: Regex specifying all protected branches
# - SHELIA_GIT_ENABLE_CREATE_PROTECTED_BRANCHES: Whether new protected branches can be created
# - SHELIA_GIT_ENABLE_DELETE_PROTECTED_BRANCHES: Whether protected branches can be deleted
# - SHELIA_GIT_PROTECTED_BRANCHES_ENABLE_TO_DELETE_REGEX: Regex of protected branches allowed for deletion
# - SHELIA_GIT_REMOTE_PROVIDER_NAME: The name of the main Git remote
#
# Example usage:
#
#   # Source the git module
#   source ./lib/git.sh
#
#   # Initialize Git policy and remote settings for this session:
#   shelia::git::init \
#     'SHELIA_GIT_PROTECTED_BRANCHES_REGEX=^(main|release/.*)$' \
#     'SHELIA_GIT_ENABLE_CREATE_PROTECTED_BRANCHES=true' \
#     'SHELIA_GIT_ENABLE_DELETE_PROTECTED_BRANCHES=false' \
#     'SHELIA_GIT_PROTECTED_BRANCHES_ENABLE_TO_DELETE_REGEX=^(release/.*)$' \
#     'SHELIA_GIT_REMOTE_PROVIDER_NAME=upstream'
#
# This will:
# - Treat 'main' and any 'release/*' branches as protected.
# - Allow creation of protected branches, but prevent deletion except for 'release/*'.
# - Use 'upstream' as the remote for protected branch operations.
#
# Initializes Git configuration variables for branch protection and remote settings.
# Supports runtime overrides using KEY=VALUE arguments.
# @param $@ Optional list of KEY=VALUE pairs to override default settings.
# @return 0 on success, 1 if an invalid parameter is provided.
function shelia::git::init() {
  : "${SHELIA_GIT_PROTECTED_BRANCHES_REGEX:=^(dev|develop|sit|uat|stage|master|sp.*/base|sp.*/integration)$}"
  : "${SHELIA_GIT_ENABLE_CREATE_PROTECTED_BRANCHES:=false}"
  : "${SHELIA_GIT_ENABLE_DELETE_PROTECTED_BRANCHES:=false}"
  : "${SHELIA_GIT_PROTECTED_BRANCHES_ENABLE_TO_DELETE_REGEX:=^(sp.*/base|sp.*/integration)$}"
  : "${SHELIA_GIT_REMOTE_PROVIDER_NAME:=origin}"

  local key_value key value
  for key_value in "$@"; do
    if [[ "$key_value" != *=* ]]; then
      shelia::logging::error "Invalid git init parameter: '$key_value'. Expected KEY=VALUE."
      return 1
    fi

    key="${key_value%%=*}"
    value="${key_value#*=}"

    case "$key" in
    SHELIA_GIT_PROTECTED_BRANCHES_REGEX)
      SHELIA_GIT_PROTECTED_BRANCHES_REGEX="$value"
      ;;
    SHELIA_GIT_ENABLE_CREATE_PROTECTED_BRANCHES)
      if [[ "$value" != true ]] && [[ "$value" != false ]]; then
        shelia::logging::error \
          "Invalid value for SHELIA_GIT_ENABLE_CREATE_PROTECTED_BRANCHES: '$value'. Use true|false."
        return 1
      fi
      SHELIA_GIT_ENABLE_CREATE_PROTECTED_BRANCHES="$value"
      ;;
    SHELIA_GIT_ENABLE_DELETE_PROTECTED_BRANCHES)
      if [[ "$value" != true ]] && [[ "$value" != false ]]; then
        shelia::logging::error \
          "Invalid value for SHELIA_GIT_ENABLE_DELETE_PROTECTED_BRANCHES: '$value'. Use true|false."
        return 1
      fi
      SHELIA_GIT_ENABLE_DELETE_PROTECTED_BRANCHES="$value"
      ;;
    SHELIA_GIT_PROTECTED_BRANCHES_ENABLE_TO_DELETE_REGEX)
      SHELIA_GIT_PROTECTED_BRANCHES_ENABLE_TO_DELETE_REGEX="$value"
      ;;
    SHELIA_GIT_REMOTE_PROVIDER_NAME)
      SHELIA_GIT_REMOTE_PROVIDER_NAME="$value"
      ;;
    *)
      shelia::logging::error "Unknown git init parameter key: '$key'."
      return 1
      ;;
    esac
  done
}

# The call to shelia::git::init is necessary here to initialize Git-related configuration variables
# and to allow runtime overrides using KEY=VALUE arguments, ensuring consistent state before other
# Git operations run in this file. If initialization fails, returning 1 safely halts dependent logic.
shelia::git::init || return 1

# Asserts that a branch name is allowed to be created according to protection policies.
# @param $1 branch_name The name of the branch to check.
# @return 0 if allowed, 1 if protected and creation is disabled.
function shelia::git::assert_branch_name_not_allow_created() {
  local branch_name="$1"
  if [[ "$branch_name" =~ $SHELIA_GIT_PROTECTED_BRANCHES_REGEX ]] &&
    [[ "$SHELIA_GIT_ENABLE_CREATE_PROTECTED_BRANCHES" == false ]]; then
    shelia::logging::error "Branch '$branch_name' is protected and cannot be created. " \
      "Please use a different branch name."
    return 1
  fi
  return 0
}

# Asserts that a branch name is allowed to be deleted according to protection policies.
# @param $1 branch_name The name of the branch to check.
# @return 0 if allowed, 1 if protected and deletion is disabled.
function shelia::git::assert_branch_name_not_allow_deleted() {
  local branch_name="$1"
  if [[ "$branch_name" =~ $SHELIA_GIT_PROTECTED_BRANCHES_REGEX ]] &&
    [[ "$SHELIA_GIT_ENABLE_DELETE_PROTECTED_BRANCHES" == false ]] &&
    [[ ! "$branch_name" =~ $SHELIA_GIT_PROTECTED_BRANCHES_ENABLE_TO_DELETE_REGEX ]]; then
    shelia::logging::error "Branch '$branch_name' is protected and cannot be deleted. " \
      "Please use a different branch name."
    return 1
  fi
  return 0
}

# A debug utility that prints the current BASH_SOURCE and FUNCNAME stack.
# @return 0 always.
function shelia::git::check_self_calling() {
  shelia::logging::debug "BASH_SOURCE: ${BASH_SOURCE[*]}"
  shelia::logging::debug "FUNCNAME: ${FUNCNAME[*]}"
  return 0
}

# Checks if a branch exists on the configured remote provider.
# @param $1 branch_name The name of the branch to check.
# @return 0 if it exists, 1 otherwise.
function shelia::git::check_branch_exists() {
  local branch_name="$1"

  if git rev-parse --verify "${SHELIA_GIT_REMOTE_PROVIDER_NAME}/$branch_name" 2>/dev/null; then
    return 0
  else
    return 1
  fi
}

# Verifies that the current directory is a Git repository and has no uncommitted changes.
# @return 0 if it is a clean repository, 1 otherwise.
function shelia::git::check_git_repo() {
  if ! git rev-parse --is-inside-work-tree &>/dev/null; then
    shelia::logging::error "Current directory is not a git repository. " \
      "Please navigate to a valid git repository."
    return 1
  fi

  if ! git diff-index --quiet HEAD --; then
    shelia::logging::error "Git working directory contains uncommitted changes. " \
      "Please commit or stash your changes before proceeding."
    return 1
  fi

  return 0
}

# Clones a Git repository with a specific branch into a project directory.
# Deletes the project directory first if it already exists.
# @param $1 project_name The name of the local directory to clone into.
# @param $2 repository The remote repository URL.
# @param $3 base_branch The branch to clone.
function shelia::git::clone_repository() {
  local project_name=$1
  local repository=$2
  local base_branch=$3

  rm -rf "$project_name"
  shelia::logging::info "Removed existing directory: '$project_name'"
  git clone -b "$base_branch" "$repository" || exit 1
  if ! cd "$project_name"; then
    shelia::logging::error "Failed to clone repository: $project_name from $repository. " \
      "Please check the repository URL and branch name."
    exit 1
  fi
  cd .. || exit 1
  shelia::logging::info "Successfully cloned repository: $repository with branch: $base_branch"
}

# Creates a new branch from a source branch and pushes it to the remote.
# Also verifies branch protection before creation.
# @param $1 branch_name The name of the new branch to create.
# @param $2 source_branch The branch to base the new branch on.
# @param $3 project_name The name of the project (for logging).
# @return 0 on success, 1 on failure.
function shelia::git::create_branch() {
  local branch_name=$1
  local source_branch=$2
  local project_name=$3

  shelia::logging::info "Creating branch '$branch_name' in project '$project_name' from '$source_branch'"

  if ! shelia::git::assert_branch_name_not_allow_created "$branch_name"; then
    shelia::logging::error "Branch $branch_name is protected and cannot be created"
    return 1
  fi

  if git ls-remote --heads "${SHELIA_GIT_REMOTE_PROVIDER_NAME}" "$branch_name" | grep "$branch_name"; then
    shelia::logging::info "Branch '$branch_name' already exists in project '$project_name'"
  else
    shelia::logging::info "Creating branch - '$branch_name' does not exist in project '$project_name'"
  fi

  shelia::git::safe_checkout "$source_branch"
  shelia::git::safe_checkout "$branch_name" "$source_branch" true false true
  if ! git push -u "${SHELIA_GIT_REMOTE_PROVIDER_NAME}" "$branch_name"; then
    shelia::logging::error "Failed to push new branch '$branch_name' to remote " \
      "(e.g. non-fast-forward or permission denied)."
    return 1
  fi

  shelia::logging::info "Successfully created branch '$branch_name' in project '$project_name'"
  return 0
}

# Deletes a branch both locally and on the remote.
# Respects branch protection policies.
# @param $1 branch_name The name of the branch to delete.
# @return 0 on success, 1 on failure.
function shelia::git::delete_branch() {
  local branch_name="$1"

  if ! shelia::git::assert_branch_name_not_allow_deleted "$branch_name"; then
    shelia::logging::error "Branch $branch_name is protected and cannot be deleted"
    return 1
  fi

  shelia::logging::info "Deleting branch '$branch_name'"

  if git branch | grep -w "$branch_name"; then
    if ! git branch -D "$branch_name"; then
      shelia::logging::error "Failed to delete local branch '$branch_name'"
      return 1
    fi
    shelia::logging::info "Deleted local branch $branch_name"
  else
    shelia::logging::info "Local branch $branch_name does not exist"
  fi

  if git ls-remote --heads "${SHELIA_GIT_REMOTE_PROVIDER_NAME}" "$branch_name" |
    grep "$branch_name"; then
    if ! git push "${SHELIA_GIT_REMOTE_PROVIDER_NAME}" --delete "$branch_name"; then
      shelia::logging::error "Failed to delete remote branch '$branch_name'. " \
        "The server may reject deletion (e.g. default branch, protected branch, " \
        "or pre-receive hook decline)."
      return 1
    fi
    shelia::logging::info "Deleted remote branch $branch_name"
  else
    shelia::logging::info "Remote branch $branch_name does not exist"
  fi

  return 0
}

# Changes the current working directory to the specified path with error handling.
# @param $1 directory_name The path to the directory to change into.
function shelia::git::safe_change_directory() {
  local directory_name="$1"
  if ! cd "${directory_name}"; then
    shelia::logging::error "Git repository directory does not exist: ${directory_name}"
    exit 1
  fi
  shelia::logging::info "Changed directory to: $(pwd)"
}

# Safely checks out a branch, handling tracking, fetching, pulling, and optional resetting.
# @param $1 branch_name The branch to checkout.
# @param $2 source_branch (Optional) If provided, create/re-create $branch_name from this source.
# @param $3 reset_hard (Optional) Whether to perform git reset --hard (default: true).
# @param $4 pull_updates (Optional) Whether to pull latest changes (default: true).
# @param $5 delete_branch (Optional) Whether to delete the branch before re-creating it (default: false).
function shelia::git::safe_checkout() {
  local branch_name="$1"
  local source_branch="${2:-}"
  local reset_hard="${3:-true}"
  local pull_updates="${4:-true}"
  local delete_branch="${5:-false}"

  if [[ -z "$source_branch" ]]; then
    shelia::logging::info "Checking out branch '$branch_name'"
    git fetch "${SHELIA_GIT_REMOTE_PROVIDER_NAME}" "$branch_name":"$branch_name"
    if ! git checkout "$branch_name"; then
      shelia::logging::error "Failed to checkout branch '$branch_name'. " \
        "Please ensure the branch exists and you have proper permissions."
      exit 1
    fi
    git branch --set-upstream-to="${SHELIA_GIT_REMOTE_PROVIDER_NAME}/${branch_name}" "$branch_name"
    if ! git pull; then
      shelia::logging::error "Failed to pull branch '$branch_name'. " \
        "Please ensure the branch exists and you have proper permissions."
      exit 1
    fi
  else
    shelia::logging::info "Checking out branch '$branch_name' from '$source_branch'"
    if ! git checkout "$source_branch" ||
      ! git pull; then
      shelia::logging::error "Failed to pull latest changes from branch '$source_branch'. " \
        "Please ensure the branch exists and you have proper permissions."
      exit 1
    fi

    if [[ "$delete_branch" == true ]]; then
      if ! shelia::git::delete_branch "$branch_name"; then
        shelia::logging::error "Aborting checkout: could not delete branch '$branch_name'."
        exit 1
      fi
    fi

    if ! git checkout -b "$branch_name" "$source_branch"; then
      shelia::logging::error "Failed to checkout branch '$branch_name' from '$source_branch'. " \
        "Please ensure the branch exists and you have proper permissions."
      exit 1
    fi
  fi

  if [[ "$reset_hard" == true ]] && ! git reset --hard; then
    shelia::logging::error "Failed to reset hard to branch '$branch_name'. " \
      "Please check your repository access and try again."
    exit 1
  fi

  if git ls-remote --heads "${SHELIA_GIT_REMOTE_PROVIDER_NAME}" "$branch_name" |
    grep "$branch_name"; then
    if [[ "$pull_updates" == true ]] &&
      ! git pull; then
      shelia::logging::error "Failed to pull latest changes from branch '$branch_name'. " \
        "Please check your network connection and repository access."
      exit 1
    fi
  fi
}

# Merges one branch into another with --no-ff and pushes the result.
# @param $1 source_branch The branch to merge from.
# @param $2 target_branch The branch to merge into.
function shelia::git::safe_merge() {
  local source_branch="$1"
  local target_branch="$2"

  shelia::git::safe_checkout "$target_branch"

  if ! git merge "${SHELIA_GIT_REMOTE_PROVIDER_NAME}/$source_branch" --no-ff; then
    shelia::logging::error "Failed to merge branch '$source_branch' into '$target_branch'. " \
      "Please check your repository access and try again."
    exit 1
  fi

  if ! git push; then
    shelia::logging::error "Failed to push changes to branch '$target_branch'. " \
      "Please check your network connection and repository access."
    exit 1
  fi

  shelia::logging::info "Successfully merged branch '$source_branch' into '$target_branch'"
}

# Stages files, commits with a message, and pushes to the current branch on the remote.
# @param $1 file_pattern The pattern of files to stage (e.g., "." or "*.sh").
# @param $2 commit_message The message for the Git commit.
function shelia::git::safe_commit_and_push() {
  local file_pattern="$1"
  local commit_message="$2"

  if ! git add "$file_pattern"; then
    shelia::logging::error "Failed to add changes to the staging area. " \
      "Please check your repository access and try again."
    exit 1
  fi

  if ! git commit -m "$commit_message"; then
    shelia::logging::error "Failed to commit and push changes. " \
      "Please check your network connection and repository access."
    exit 1
  fi

  if ! git push -u "${SHELIA_GIT_REMOTE_PROVIDER_NAME}" HEAD; then
    shelia::logging::error "Failed to push changes. " \
      "Please check your network connection and repository access."
    exit 1
  fi
}
