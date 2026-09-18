#!/usr/bin/env bash
set -euo pipefail

: "${GITHUB_WORKSPACE:?Check out the application before using this action}"
: "${RUNNER_TEMP:?RUNNER_TEMP is required}"
: "${GITHUB_OUTPUT:?GITHUB_OUTPUT is required}"
: "${SDKMAN_RUN:?The run input must contain a build command}"
if [[ ${RUNNER_OS:-} != Linux ]]; then
    printf 'ERROR: this action requires a Linux runner\n' >&2
    exit 1
fi
if [[ ${SDKMAN_CACHE:-true} != true && ${SDKMAN_CACHE:-true} != false ]]; then
    printf 'ERROR: cache must be true or false\n' >&2
    exit 1
fi

workspace=$(cd -- "$GITHUB_WORKSPACE" && pwd -P)
project=$(cd -- "$workspace/${SDKMAN_WORKING_DIRECTORY:-.}" && pwd -P)
if [[ "$project" != "$workspace" && "$project" != "$workspace/"* ]] \
    || [[ "$project$RUNNER_TEMP" == *$'\n'* || "$project$RUNNER_TEMP" == *$'\r'* ]] \
    || [[ ! -s "$project/.sdkmanrc" ]]; then
    printf 'ERROR: working-directory must be inside the checkout and contain a nonempty .sdkmanrc\n' >&2
    exit 1
fi

rc_hash=$(sha256sum "$project/.sdkmanrc")
os_hash=$(sha256sum /etc/os-release)
installation=$(mktemp -d "$RUNNER_TEMP/sdkman-ci.XXXXXX")
printf '%s\n' \
    "sdkman-dir=$installation/sdkman" \
    "candidates-dir=$RUNNER_TEMP/sdkman-ci-candidates" \
    "working-directory=$project" \
    "rc-hash=${rc_hash%% *}" \
    "os-hash=${os_hash%% *}" >> "$GITHUB_OUTPUT"
