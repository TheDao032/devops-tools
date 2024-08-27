#!/bin/bash

log_msg() {
    local LEVEL="$1"
    shift
    local MESSAGE="$@"
    local TIMESTAMP=$(date +"%Y-%m-%d %H:%M:%S")

    # Colorize the message
    case $LEVEL in
        "error")
          COLOR_CODE="\e[31m" ;; # Red
        "success")
          COLOR_CODE="\e[32m" ;; # Green
        "warn")
          COLOR_CODE="\e[33m" ;; # Yellow
        "debug")
          COLOR_CODE="\e[34m" ;; # Blue
        "info")
          COLOR_CODE="\e[45m" ;; # Magenta
        *)
          COLOR_CODE="\e[0m" ;;  # Default to no color
    esac

    # Log the colored message
    # echo -e "${COLOR_CODE}${TIMESTAMP} - ${MESSAGE}\e[0m"
    printf "${COLOR_CODE}${TIMESTAMP} - ${MESSAGE}\e[0m\n"
}

function log_debug() {
  if [ $# -eq 0 ]; then
    return 0
  fi
  log_msg debug "${@}"
  return $?
}

function log_error() {
  if [ $# -eq 0 ]; then
    return 0
  fi
  log_msg error "${@}"
  return $?
}

function log_warn() {
  if [ $# -eq 0 ]; then
    return 0
  fi
  log_msg warn "${@}"
  return $?
}

function log_info() {
  if [ $# -eq 0 ]; then
    return 0
  fi
  log_msg info "${@}"
  return $?
}

function log_success() {
  if [ $# -eq 0 ]; then
    return 0
  fi
  log_msg success "${@}"
  return $?
}
