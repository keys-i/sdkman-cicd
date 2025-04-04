#!/usr/bin/env bash
set -euo pipefail

project_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
configure="$project_dir/docker/configure-sdkman.sh"
test_dir=$(mktemp -d)
trap 'rm -rf -- "$test_dir"' EXIT

# Keep child shells isolated from any SDKMAN installation on the host
export BASH_ENV=/dev/null
export SDKMAN_DIR="$test_dir/sdkman home"
mkdir -p "$SDKMAN_DIR/bin" "$SDKMAN_DIR/etc"
initializer="$SDKMAN_DIR/bin/sdkman-init.sh"
config="$SDKMAN_DIR/etc/config"

cat > "$initializer" <<'INIT'
export SDKMAN_CANDIDATES_DIR="${SDKMAN_DIR}/candidates"
export JAVA_HOME="${SDKMAN_CANDIDATES_DIR}/java/current"
export PATH="${JAVA_HOME}/bin:${PATH}"
INIT
cat > "$config" <<'CONFIG'
sdkman_auto_answer=false
sdkman_colour_enable=true
sdkman_selfupdate_feature=true
sdkman_checksum_enable=false
sdkman_auto_complete=true
sdkman_auto_env=true
sdkman_healthcheck_enable=true
sdkman_curl_retry=0
sdkman_curl_retry_max_time=120
sdkman_curl_connect_timeout=11
CONFIG

bash "$configure"

check_candidate_paths() {
    bash -eu -c '
        source "$SDKMAN_DIR/bin/sdkman-init.sh"
        [[ "$SDKMAN_CANDIDATES_DIR" == "$1" ]]
        [[ "$JAVA_HOME" == "$1/java/current" ]]
        [[ "$PATH" == "$JAVA_HOME/bin:"* ]]
    ' _ "$1"
}
unset SDKMAN_CANDIDATES_DIR
check_candidate_paths "$SDKMAN_DIR/candidates"
SDKMAN_CANDIDATES_DIR='' check_candidate_paths "$SDKMAN_DIR/candidates"
SDKMAN_CANDIDATES_DIR="$test_dir/cache with spaces" check_candidate_paths "$test_dir/cache with spaces"

# Evaluate the config so existing settings must be overridden or preserved
bash -eu -c '
    source "$SDKMAN_DIR/etc/config"
    [[ "$sdkman_auto_answer" == true ]]
    [[ "$sdkman_colour_enable" == false ]]
    [[ "$sdkman_selfupdate_feature" == false ]]
    [[ "$sdkman_checksum_enable" == true ]]
    [[ "$sdkman_auto_complete" == false ]]
    [[ "$sdkman_auto_env" == false ]]
    [[ "$sdkman_healthcheck_enable" == false ]]
    [[ "$sdkman_curl_retry" == 3 ]]
    [[ "$sdkman_curl_retry_max_time" == 60 ]]
    [[ "$sdkman_curl_connect_timeout" == 11 ]]
'

printf 'export SDKMAN_CANDIDATES_DIR=/changed/upstream/path\n' > "$initializer"
cp "$initializer" "$test_dir/expected-init"
cp "$config" "$test_dir/expected-config"
if bash "$configure" > "$test_dir/error" 2>&1; then
    printf 'ERROR: accepted an unrecognized initializer\n' >&2
    exit 1
fi
grep -Fq 'SDKMAN initializer changed' "$test_dir/error"
cmp "$initializer" "$test_dir/expected-init"
cmp "$config" "$test_dir/expected-config"

if env -u SDKMAN_DIR bash "$configure" > "$test_dir/error" 2>&1; then
    printf 'ERROR: accepted a missing SDKMAN_DIR\n' >&2
    exit 1
fi
grep -Fq 'SDKMAN_DIR must name the SDKMAN installation' "$test_dir/error"

printf 'SDKMAN configuration checks passed\n'
