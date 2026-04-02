# shellcheck shell=bash
# Maven toolchain checks and build/deploy (SRP: Maven integration).

# shellcheck source=./shell.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/shell.sh"

# Version check: maven.sh requires Bash 3.0+ (inherits shell.sh dependency)
shelia::bootstrap::require_bash_version "maven.sh" "$__SHELIA_BASH_MAVEN_MIN_MAJOR" "$__SHELIA_BASH_MAVEN_MIN_MINOR"
shelia::shell::begin_module MAVEN || return 0
# shellcheck source=./git.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/git.sh"

# Resolves the Maven settings file path.
# Handles '~' expansion and environment variable interpolation.
# Sets SHELIA_MAVEN_SETTINGS_FILE to the resolved path.
# Exits if the path contains unsupported command substitution.
function shelia::maven::resolve_maven_settings_file() {
  local raw_settings_file="${SHELIA_MAVEN_SETTINGS_FILE:-}"
  if [[ -z "$raw_settings_file" ]]; then
    raw_settings_file="~/.m2/settings.xml"
  fi

  local resolved_settings_file="$raw_settings_file"
  if [[ "$resolved_settings_file" == "~"* ]]; then
    resolved_settings_file="${resolved_settings_file/#\~/$HOME}"
  fi

  if [[ "$resolved_settings_file" == *'$('* || "$resolved_settings_file" == *'`'* ]]; then
    shelia::logging::error "SHELIA_MAVEN_SETTINGS_FILE contains unsupported command substitution: " \
      "$raw_settings_file"
    exit 1
  fi

  if [[ "$resolved_settings_file" == *'$'* ]]; then
    resolved_settings_file="$(eval "printf '%s' \"$resolved_settings_file\"")"
  fi

  SHELIA_MAVEN_SETTINGS_FILE="$resolved_settings_file"
}

# Checks if the Maven settings file exists.
# Calls resolve_maven_settings_file first.
# Exits with an error message if the file is missing.
function shelia::maven::check_maven_settings() {
  shelia::maven::resolve_maven_settings_file
  if [ ! -f "$SHELIA_MAVEN_SETTINGS_FILE" ]; then
    shelia::logging::error "Maven settings file not found at: $SHELIA_MAVEN_SETTINGS_FILE. " \
      "Please ensure the file exists and is accessible."
    exit 1
  fi
}

# Verifies that the Maven Help Plugin is available and functional.
# Attempts to evaluate project.version to test the plugin.
# Exits if the plugin cannot be executed.
function shelia::maven::check_maven_help_plugin() {
  local plugin_version="3.2.0"

  mvn org.apache.maven.plugins:maven-help-plugin:${plugin_version}:evaluate \
    -Dexpression=project.version -q -DforceStdout 2>&1

  # shellcheck disable=SC2181
  if [[ $? -ne 0 ]]; then
    shelia::logging::error "Maven Help Plugin " \
      "(org.apache.maven.plugins:maven-help-plugin:${plugin_version}) " \
      "is not available or failed to run. Please ensure it is accessible."
    exit 1
  fi
}

# Updates the Maven project version using the versions:set goal.
# @param $1 new_version The version string to set.
# @param $2 generate_backup Whether to generate backup POM files (default: false).
# @return 0 on success, 1 on failure.
function shelia::maven::update_maven_version() {
  local new_version=$1
  local generate_backup="${2:-false}"

  if mvn versions:set -DnewVersion="$new_version" -DgenerateBackupPoms="$generate_backup"; then
    shelia::logging::info "Successfully updated Maven project version to: $new_version"
    return 0
  else
    shelia::logging::error "Failed to update Maven project version to '$new_version'. " \
      "Please check your Maven configuration and try again."
    return 1
  fi
}

# Retrieves the current Maven project version.
# Uses the Maven Help Plugin to evaluate project.version.
# @return The current version string printed to stdout.
function shelia::maven::get_maven_current_version() {
  mvn org.apache.maven.plugins:maven-help-plugin:3.2.0:evaluate \
    -Dexpression=project.version -q -DforceStdout
}

# Verifies if the current Maven project version matches an expected version.
# @param $1 expected_version The version string to verify against.
# @return 0 if versions match, 1 otherwise.
function shelia::maven::verify_maven_version() {
  local expected_version=$1
  local current_version

  current_version="$(shelia::maven::get_maven_current_version)"

  if [[ "$current_version" == "$expected_version" ]]; then
    return 0
  else
    shelia::logging::error "Version verification failed: expected '$expected_version', " \
      "but found '$current_version'."
    return 1
  fi
}

# Performs a Maven install ('mvn clean install') for a project or specific module.
# Switches to the project directory and branch before installing.
# @param $1 is_install_all_modules Boolean (true/false) to install all modules or a specific one.
# @param $2 project_name The name/directory of the Maven project.
# @param $3 branch_name The Git branch to checkout before installing.
# @param $4 target_version The version being installed (used for logging).
# @param $5 module_name The specific module to install (required if $1 is false).
function shelia::maven::maven_install() {
  local is_install_all_modules=$1
  local project_name=$2
  local branch_name=$3
  local target_version=$4
  local module_name="${5:-}"

  shelia::maven::resolve_maven_settings_file
  shelia::git::safe_change_directory "${project_name}"
  shelia::git::safe_checkout "${branch_name}"

  if [[ "$is_install_all_modules" == true ]]; then
    if mvn clean install -T 1C -Dmaven.test.skip -DskipTests -U -s "$SHELIA_MAVEN_SETTINGS_FILE"; then
      shelia::logging::info "Successfully installed ${project_name} ${branch_name} " \
        "${target_version} (all modules)"
    else
      shelia::logging::error "Failed to install ${project_name} ${branch_name} " \
        "${target_version} (all modules)"
      exit 1
    fi
  else
    if mvn clean install -N -U -s "$SHELIA_MAVEN_SETTINGS_FILE" &&
      mvn clean install -pl "${module_name}" -T 1C -Dmaven.test.skip \
        -DskipTests -U -s "$SHELIA_MAVEN_SETTINGS_FILE"; then
      shelia::logging::info "Successfully installed ${project_name}-${module_name} " \
        "${branch_name} ${target_version}"
    else
      shelia::logging::error "Failed to install ${project_name}-${module_name} " \
        "${branch_name} ${target_version}"
      exit 1
    fi
  fi

  shelia::git::safe_change_directory "-"
  shelia::logging::info "Completed installation of ${project_name} ${branch_name} ${target_version}"
}

# Performs a Maven deploy ('mvn clean deploy') for a project or specific module.
# Switches to the project directory and branch before deploying.
# @param $1 is_deploy_all_modules Boolean (true/false) to deploy all modules or a specific one.
# @param $2 project_name The name/directory of the Maven project.
# @param $3 branch_name The Git branch to checkout before deploying.
# @param $4 target_version The version being deployed (used for logging).
# @param $5 module_name The specific module to deploy (required if $1 is false).
function shelia::maven::maven_deploy() {
  local is_deploy_all_modules=$1
  local project_name=$2
  local branch_name=$3
  local target_version=$4
  local module_name="${5:-}"

  shelia::maven::resolve_maven_settings_file
  shelia::logging::warn "Preparing to deploy integration branch for ${project_name}"

  shelia::git::safe_change_directory "${project_name}"
  shelia::git::safe_checkout "${branch_name}"

  if [[ "$is_deploy_all_modules" == true ]]; then
    if mvn clean deploy -Dmaven.test.skip -DskipTests -U -s "$SHELIA_MAVEN_SETTINGS_FILE"; then
      shelia::logging::info "Successfully deployed ${project_name} ${branch_name} ${target_version}"
    else
      shelia::logging::error "Failed to deploy ${project_name} ${branch_name} ${target_version}"
      exit 1
    fi
  else
    if mvn clean deploy -N -U -s "$SHELIA_MAVEN_SETTINGS_FILE" &&
      mvn clean deploy -pl "${module_name}" -T 1C -Dmaven.test.skip \
        -DskipTests -U -s "$SHELIA_MAVEN_SETTINGS_FILE"; then
      shelia::logging::info "Successfully deployed ${project_name}-${module_name} " \
        "${branch_name} ${target_version}"
    else
      shelia::logging::error "Failed to deploy ${project_name}-${module_name} " \
        "${branch_name} ${target_version}"
      exit 1
    fi
  fi

  shelia::git::safe_change_directory "-"
  shelia::logging::warn "Completed ${project_name} ${branch_name} ${target_version} deployment"
}
