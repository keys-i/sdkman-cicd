#!/usr/bin/env bash
set -euo pipefail

project_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
test_dir=$(mktemp -d)
trap 'rm -rf -- "$test_dir"' EXIT
export BASH_ENV=/dev/null SDKMAN_DIR="$test_dir/sdkman"
export INSTALL_CALLS="$test_dir/calls" INSTALL_STATUS=0

# Stub the download so no SDKMAN or GitHub services are contacted
curl() {
    [[ $* == '--silent --location https://get.sdkman.io?ci=true&rcupdate=false --output '* ]] || return 99
    grep -Fxq 'proto = "=https"' "$CURL_HOME/.curlrc" || return 99
    grep -Fxq 'proto-redir = "=https"' "$CURL_HOME/.curlrc" || return 99
    printf 'download\n' >> "$INSTALL_CALLS"
    [[ $INSTALL_STATUS == 0 ]] || return "$INSTALL_STATUS"
    cat > "$5" <<'INSTALL'
[[ ! -e "$SDKMAN_DIR" ]] || exit 91
mkdir -p "$SDKMAN_DIR/bin" "$SDKMAN_DIR/etc"
: > "$SDKMAN_DIR/etc/config"
cat > "$SDKMAN_DIR/bin/sdkman-init.sh" <<'INIT'
export SDKMAN_CANDIDATES_DIR="${SDKMAN_DIR}/candidates"
sdk() { [[ "$*" == version ]]; }
INIT
INSTALL
}
export -f curl
bash "$project_dir/docker/install-sdkman.sh"
[[ $(cat "$INSTALL_CALLS") == download ]] || exit 1
grep -Fxq 'sdkman_checksum_enable=true' "$SDKMAN_DIR/etc/config"

: > "$INSTALL_CALLS"
if bash "$project_dir/docker/install-sdkman.sh" > "$test_dir/error" 2>&1; then
    printf 'ERROR: installer accepted an existing directory\n' >&2
    exit 1
fi
[[ ! -s "$INSTALL_CALLS" ]] || exit 1

export SDKMAN_DIR="$test_dir/failed-install" INSTALL_STATUS=23
status=0
bash "$project_dir/docker/install-sdkman.sh" || status=$?
[[ $status == 23 && ! -e "$SDKMAN_DIR" ]] || exit 1
printf 'SDKMAN installer checks passed\n'
