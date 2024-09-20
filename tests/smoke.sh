#!/usr/bin/env bash
set -e -o pipefail

[[ $(type -t sdk) == function ]]
[[ "$SDKMAN_CANDIDATES_DIR" == "$SDKMAN_DIR/candidates" ]]
[[ "${sdkman_auto_answer:-}" == true ]]
[[ "${sdkman_selfupdate_feature:-}" == false ]]
[[ "${sdkman_colour_enable:-}" == false ]]
[[ "${sdkman_checksum_enable:-}" == true ]]
command -v shasum > /dev/null

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
