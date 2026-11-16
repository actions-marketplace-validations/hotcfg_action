#!/usr/bin/env bash
# Runs one hotcfg command for the action. Every input arrives as an
# environment variable (set in action.yml), never pasted into the script, so
# input values can't inject shell commands.
#
# The CLI does the work: it checks files, prints errors as GitHub
# annotations (GITHUB_ACTIONS=true) and, with --json, prints the API's
# response, which becomes the step's outputs.
set -euo pipefail

fail() {
  echo "::error::$1"
  exit 1
}
need() {
  [ -n "$2" ] || fail "The '$1' input is required for command '$INPUT_COMMAND'"
}
need_key() {
  [ -n "${HOTCFG_API_KEY:-}" ] || fail "The 'api-key' input is required for command '$INPUT_COMMAND' (pass it from a secret)"
}

# An empty input must not shadow the CLI's defaults.
[ -n "${HOTCFG_API_URL:-}" ] || unset HOTCFG_API_URL
[ -n "${HOTCFG_API_KEY:-}" ] || unset HOTCFG_API_KEY

# extra-args is split on whitespace; quotes are not interpreted and nothing
# is expanded.
extra=()
if [ -n "${INPUT_EXTRA_ARGS:-}" ]; then
  read -r -a extra <<< "$INPUT_EXTRA_ARGS"
fi

case "$INPUT_COMMAND" in
  install)
    exit 0
    ;;
  validate)
    need file "$INPUT_FILE"
    args=(validate "$INPUT_FILE")
    if [ -n "$INPUT_BIN" ]; then
      need_key
      args+=(--bin "$INPUT_BIN")
    fi
    exec hotcfg "${args[@]}" ${extra[@]+"${extra[@]}"}
    ;;
  push)
    need file "$INPUT_FILE"
    need bin "$INPUT_BIN"
    need environment "$INPUT_ENVIRONMENT"
    need_key
    args=(push "$INPUT_FILE" --bin "$INPUT_BIN" --env "$INPUT_ENVIRONMENT" --json)
    ;;
  promote)
    need bin "$INPUT_BIN"
    need from-environment "$INPUT_FROM_ENVIRONMENT"
    need environment "$INPUT_ENVIRONMENT"
    need_key
    args=(promote "$INPUT_BIN" --from "$INPUT_FROM_ENVIRONMENT" --to "$INPUT_ENVIRONMENT" --json)
    ;;
  *)
    fail "Unknown command '$INPUT_COMMAND': use validate, push, promote or install"
    ;;
esac

# Errors and annotations go to stderr, straight to the log; stdout is the
# API's JSON response.
result="$(hotcfg "${args[@]}" ${extra[@]+"${extra[@]}"})"
echo "$result"

field() { jq -r --arg k "$1" '.[$k] // empty | tostring' <<< "$result"; }
version="$(field version)"
hash="$(field hash)"
from_version="$(field promoted_from_version)"
{
  echo "version=$version"
  echo "hash=$hash"
  echo "promoted-from-version=$from_version"
} >> "$GITHUB_OUTPUT"

{
  echo "### hotcfg"
  if [ "$INPUT_COMMAND" = push ]; then
    echo "Pushed \`$INPUT_FILE\` to \`$INPUT_BIN\` ($INPUT_ENVIRONMENT): **v$version**"
  else
    echo "Promoted \`$INPUT_BIN\` $INPUT_FROM_ENVIRONMENT v$from_version → $INPUT_ENVIRONMENT **v$version**"
  fi
} >> "$GITHUB_STEP_SUMMARY"
