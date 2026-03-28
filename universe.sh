#!/bin/bash
# shellcheck disable=SC2034
# Convenient entry: loads the full ShelIA public API. Each file under lib/ sources
# its own dependencies, so scripts may also source lib/<module>.sh directly.

__SHELIA_HOME="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)" || exit 1

# shellcheck source=lib/shell.sh
source "${__SHELIA_HOME}/lib/shell.sh"
# shellcheck source=lib/logging.sh
source "${__SHELIA_HOME}/lib/logging.sh"
# shellcheck source=lib/git.sh
source "${__SHELIA_HOME}/lib/git.sh"
# shellcheck source=lib/maven.sh
source "${__SHELIA_HOME}/lib/maven.sh"
# shellcheck source=lib/color.sh
source "${__SHELIA_HOME}/lib/color.sh"
# shellcheck source=lib/workspace.sh
source "${__SHELIA_HOME}/lib/workspace.sh"

unset __SHELIA_HOME
