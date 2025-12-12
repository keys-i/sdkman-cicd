#!/usr/bin/env bash
set -e -o pipefail

[[ $(id -u) == "${1:?Expected container UID is required}" ]]
[[ $(locale charmap) == UTF-8 ]]
[[ $(type -t sdk) == function ]]
[[ "$SDKMAN_CANDIDATES_DIR" == "$SDKMAN_DIR/candidates" ]]
for candidate_command in java javac kotlinc; do
    if command -v "$candidate_command" > /dev/null; then
        printf 'ERROR: base image contains preinstalled %s\n' "$candidate_command" >&2
        exit 1
    fi
done
[[ "${sdkman_auto_answer:-}" == true ]]
[[ "${sdkman_selfupdate_feature:-}" == false ]]
[[ "${sdkman_colour_enable:-}" == false ]]
[[ "${sdkman_checksum_enable:-}" == true ]]
[[ "${sdkman_curl_retry:-}" == 3 ]]
[[ "${sdkman_curl_retry_max_time:-}" == 60 ]]
command -v shasum > /dev/null

# Prevent inherited functions from masking missing shell startup hooks
(
    unset -f sdk
    bash -lc '[[ $(type -t sdk) == function ]]'
    unset BASH_ENV
    bash -ic '[[ $(type -t sdk) == function ]]'
    bash -lic '[[ $(type -t sdk) == function ]]'
)

test_dir=$(mktemp -d)
trap 'rm -rf -- "$test_dir"' EXIT

# Empty SDK directories exercise cache activation without downloading a JDK
mkdir -p "$test_dir/cache/java/smoke/bin" "$test_dir/cache/kotlin/smoke/bin"
ln -s smoke "$test_dir/cache/java/current"
ln -s smoke "$test_dir/cache/kotlin/current"
printf 'java=smoke\nkotlin=smoke\n' > "$test_dir/.sdkmanrc"

cd "$test_dir"
SDKMAN_CANDIDATES_DIR="$test_dir/cache" bash -e -o pipefail -c '
    if [[ "$SDKMAN_CANDIDATES_DIR" != "$PWD/cache" ]]; then
        printf "ERROR: SDKMAN ignored the custom candidate directory\n" >&2
        exit 1
    fi
    [[ "$JAVA_HOME" == "$PWD/cache/java/current" ]]
    [[ "$KOTLIN_HOME" == "$PWD/cache/kotlin/current" ]]
    [[ ":$PATH:" == *":$JAVA_HOME/bin:"* ]]
    [[ ":$PATH:" == *":$KOTLIN_HOME/bin:"* ]]
    sdk env
    [[ "$JAVA_HOME" == "$PWD/cache/java/smoke" ]]
    [[ "$KOTLIN_HOME" == "$PWD/cache/kotlin/smoke" ]]
    [[ ":$PATH:" == *":$JAVA_HOME/bin:"* ]]
    [[ ":$PATH:" == *":$KOTLIN_HOME/bin:"* ]]

    printf "java=missing-smoke-version\n" > .sdkmanrc
    if sdk env; then
        printf "ERROR: SDKMAN accepted an uninstalled version\n" >&2
        exit 1
    fi
    rm .sdkmanrc
    if sdk env; then
        printf "ERROR: SDKMAN accepted a missing .sdkmanrc\n" >&2
        exit 1
    fi
'

printf 'SDKMAN shell and candidate cache checks passed\n'
