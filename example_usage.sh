#!/usr/bin/env bash

# 1. Source the Shelia library
# This loads all modules: logging, color, git, maven, shell, and workspace.
source "$(dirname "${BASH_SOURCE[0]}")/universe.sh"

# 2. Use the logging module
shelia::logging::banner "Shelia Logging Example"
shelia::logging::info "This is an informational message."
shelia::logging::warn "This is a warning message."
shelia::logging::debug "This is a debug message (only visible if configured)."

# 3. Use the color module for custom formatting
echo -e "You can also use $(shelia::color::bold "bold") and $(shelia::color::cyan "cyan") text manually."
echo -e "Or even $(shelia::color::success "success") and $(shelia::color::failure "failure") indicators."

# 4. Working with Maven (Example of checking settings)
shelia::logging::banner "Shelia Maven Example"
# This will resolve and check if your ~/.m2/settings.xml exists
# (It might fail if you don't have Maven installed, which is fine for an example)
if command -v mvn &>/dev/null; then
  shelia::maven::resolve_maven_settings_file
  shelia::logging::info "Resolved Maven settings at: $SHELIA_MAVEN_SETTINGS_FILE"
else
  shelia::logging::warn "Maven is not installed, skipping maven checks."
fi

# 5. Git Module Examples
shelia::logging::banner "Shelia Git Example"

# Check if we are in a clean git repository
if shelia::git::check_git_repo; then
  shelia::logging::info "Current directory is a clean Git repository."
else
  shelia::logging::warn "Git repository has uncommitted changes or is not a repo."
fi

# Example of customizing git policies (regex for protected branches)
shelia::git::init \
  'SHELIA_GIT_PROTECTED_BRANCHES_REGEX=^(main|master|production)$' \
  'SHELIA_GIT_ENABLE_DELETE_PROTECTED_BRANCHES=false'

# Check if a branch is protected before doing something
branch_to_check="main"
if [[ "$branch_to_check" =~ $SHELIA_GIT_PROTECTED_BRANCHES_REGEX ]]; then
  shelia::logging::warn "Branch '$branch_to_check' is PROTECTED by the current policy."
fi

# Note: The following commands are destructive or require remote access,
# so they are commented out in this example script.
#
# Create a new branch from 'main'
# shelia::git::create_branch "feature/cool-stuff" "main" "my-project"
#
# Safe checkout with automatic pull and reset
# shelia::git::safe_checkout "develop"
#
# Merge a feature branch into develop
# shelia::git::safe_merge "feature/cool-stuff" "develop"

# 6. Error handling demonstration
# Shelia sets up an automatic error trap when logging is loaded.
# To demonstrate, uncomment the next line:
# ls /non-existent-directory
