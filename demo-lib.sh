# SPDX-FileCopyrightText: Copyright 2026 Carabiner Systems, Inc
# SPDX-License-Identifier: Apache-2.0
#
# Shared output helpers for the demo scripts: colorized step headings, an
# explanation of what is about to happen, and every command printed before
# it runs. Colors are off when stdout is not a terminal or NO_COLOR is set.

if [[ -t 1 && -z "${NO_COLOR:-}" ]]; then
  C_STEP=$'\e[1;36m'   # bold cyan: step heading
  C_NOTE=$'\e[2m'      # dim: explanation
  C_CMD=$'\e[1;33m'    # bold yellow: the command
  C_OK=$'\e[1;32m'     # bold green: success
  C_ERR=$'\e[1;31m'    # bold red: failure
  C_OFF=$'\e[0m'
else
  C_STEP='' C_NOTE='' C_CMD='' C_OK='' C_ERR='' C_OFF=''
fi

# step "heading" ["explanation" ...]: announces what is about to happen.
step() {
  printf '\n%s==> %s%s\n' "$C_STEP" "$1" "$C_OFF"
  shift
  for line in "$@"; do printf '%s    %s%s\n' "$C_NOTE" "$line" "$C_OFF"; done
}

# run cmd args...: prints the command, then runs it. Its output is left
# alone, so it can be piped.
run() {
  local shown=''
  for arg in "$@"; do
    if [[ "$arg" =~ [[:space:]\|\&\;\<\>\(\)\$\`\"\'] ]]; then
      shown+=" '${arg//\'/\'\\\'\'}'"
    else
      shown+=" $arg"
    fi
  done
  printf '%s$%s%s\n' "$C_CMD" "$shown" "$C_OFF" >&2
  "$@"
}

ok()   { printf '\n%s✔ %s%s\n' "$C_OK" "$*" "$C_OFF"; }
fail() { printf '\n%s✘ %s%s\n' "$C_ERR" "$*" "$C_OFF" >&2; exit 1; }
