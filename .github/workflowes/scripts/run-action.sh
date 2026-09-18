#!/usr/bin/env bash
set -e -o pipefail

: "${SDKMAN_DIR:?SDKMAN_DIR is required}"
: "${SDKMAN_RUN:?The run input must contain a build command}"
# shellcheck disable=SC1091
source "$SDKMAN_DIR/bin/sdkman-init.sh"
sdk env || sdk env install

# A fresh shell loads newly installed candidate paths before selecting the project SDKs
export BASH_ENV="$SDKMAN_DIR/bin/sdkman-init.sh"
exec bash -e -o pipefail -c 'sdk env; eval "$SDKMAN_RUN"'
