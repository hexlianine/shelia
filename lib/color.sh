# shellcheck shell=bash
# Color helpers (SRP: ANSI color formatting only).

# shellcheck source=./shell.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/shell.sh"
shelia::shell::begin_module COLOR || return 0
SUCCESS_COLOR_TAG="\e[32m"
FAILURE_COLOR_TAG="\e[31m"
WARNING_COLOR_TAG="\e[33m"
INFO_COLOR_TAG="\e[36m"
DEBUG_COLOR_TAG="\e[90m"
END_COLOR_TAG="\e[0m"

BLACK_COLOR_TAG="\e[30m"
WHITE_COLOR_TAG="\e[97m"
RED_COLOR_TAG="\e[31m"
GREEN_COLOR_TAG="\e[32m"
YELLOW_COLOR_TAG="\e[33m"
BLUE_COLOR_TAG="\e[34m"
MAGENTA_COLOR_TAG="\e[35m"
CYAN_COLOR_TAG="\e[36m"
GRAY_COLOR_TAG="\e[90m"

BOLD_STYLE_TAG="\e[1m"
UNDERLINE_STYLE_TAG="\e[4m"
DIM_STYLE_TAG="\e[2m"

function shelia::color::wrap() {
  local color_tag="$1"
  shift 1
  printf '%b%s%b' "${color_tag}" "$*" "${END_COLOR_TAG}"
}

function shelia::color::success() {
  shelia::color::wrap "${SUCCESS_COLOR_TAG}" "$@"
}

function shelia::color::failure() {
  shelia::color::wrap "${FAILURE_COLOR_TAG}" "$@"
}

function shelia::color::warning() {
  shelia::color::wrap "${WARNING_COLOR_TAG}" "$@"
}

function shelia::color::info() {
  shelia::color::wrap "${INFO_COLOR_TAG}" "$@"
}

function shelia::color::debug() {
  shelia::color::wrap "${DEBUG_COLOR_TAG}" "$@"
}

function shelia::color::black() {
  shelia::color::wrap "${BLACK_COLOR_TAG}" "$@"
}

function shelia::color::white() {
  shelia::color::wrap "${WHITE_COLOR_TAG}" "$@"
}

function shelia::color::red() {
  shelia::color::wrap "${RED_COLOR_TAG}" "$@"
}

function shelia::color::green() {
  shelia::color::wrap "${GREEN_COLOR_TAG}" "$@"
}

function shelia::color::yellow() {
  shelia::color::wrap "${YELLOW_COLOR_TAG}" "$@"
}

function shelia::color::blue() {
  shelia::color::wrap "${BLUE_COLOR_TAG}" "$@"
}

function shelia::color::magenta() {
  shelia::color::wrap "${MAGENTA_COLOR_TAG}" "$@"
}

function shelia::color::cyan() {
  shelia::color::wrap "${CYAN_COLOR_TAG}" "$@"
}

function shelia::color::gray() {
  shelia::color::wrap "${GRAY_COLOR_TAG}" "$@"
}

function shelia::color::bold() {
  shelia::color::wrap "${BOLD_STYLE_TAG}" "$@"
}

function shelia::color::underline() {
  shelia::color::wrap "${UNDERLINE_STYLE_TAG}" "$@"
}

function shelia::color::dim() {
  shelia::color::wrap "${DIM_STYLE_TAG}" "$@"
}
