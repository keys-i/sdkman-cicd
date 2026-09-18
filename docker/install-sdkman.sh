#!/usr/bin/env bash
set -e -o pipefail

: "${SDKMAN_DIR:?SDKMAN_DIR must name a new installation directory}"
if [[ -e "$SDKMAN_DIR" ]]; then
    printf 'ERROR: SDKMAN_DIR must not already exist: %s\n' "$SDKMAN_DIR" >&2
    exit 1
fi

installer_dir=$(mktemp -d)
trap 'rm -rf -- "$installer_dir"' EXIT

# Apply the download policy to the installer and its child curl processes
printf '%s\n' \
    'fail' \
    'show-error' \
    'proto = "=https"' \
    'proto-redir = "=https"' \
    'connect-timeout = 10' \
    'max-time = 120' \
    'retry = 3' \
    'retry-max-time = 180' > "$installer_dir/.curlrc"
CURL_HOME="$installer_dir" curl --silent --location \
    'https://get.sdkman.io?ci=true&rcupdate=false' \
    --output "$installer_dir/install.sh"
CURL_HOME="$installer_dir" bash "$installer_dir/install.sh"
bash "$(dirname -- "$0")/configure-sdkman.sh"
# shellcheck disable=SC1091
source "$SDKMAN_DIR/bin/sdkman-init.sh"
sdk version
