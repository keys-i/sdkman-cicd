#!/usr/bin/env bash
set -euo pipefail

project_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
test_dir=$(mktemp -d)
trap 'rm -rf -- "$test_dir"' EXIT
export PUBLISH_IMAGE=docker.io/example/sdkman-ci:v1.2.3
export GITHUB_STEP_SUMMARY="$test_dir/summary"
export PUSH_CALLS="$test_dir/push-calls"
export PUSH_OUTPUT PUSH_STATUS=0
printf -v digest 'sha256:%064d' 0
digest_line="v1.2.3: digest: $digest size: 1234"

# Stub only Docker so these checks cannot publish an image
docker() {
    [[ $# == 3 && $1 == image && $2 == push && $3 == "$PUBLISH_IMAGE" ]] || return 99
    printf 'push\n' >> "$PUSH_CALLS"
    printf '%s\n' "$PUSH_OUTPUT"
    return "$PUSH_STATUS"
}
export -f docker

PUSH_OUTPUT=$(printf 'The push refers to repository [docker.io/example/sdkman-ci]\nlayer: Pushed\n%s\n' "$digest_line")
printf 'Earlier step summary\n' > "$GITHUB_STEP_SUMMARY"
bash "$project_dir/.github/workflowes/scripts/publish-image.sh" > "$test_dir/output"
grep -Fxq "$digest_line" "$test_dir/output"
grep -Fxq 'Earlier step summary' "$GITHUB_STEP_SUMMARY"
grep -Fxq "    $PUBLISH_IMAGE" "$GITHUB_STEP_SUMMARY"
grep -Fxq "    docker.io/example/sdkman-ci@$digest" "$GITHUB_STEP_SUMMARY"

: > "$PUSH_CALLS"
for image in sdkman-ci docker.io/example/sdkman-ci registry.example:5000/sdkman-ci \
    docker.io/example/sdkman-ci: docker.io/example/sdkman-ci:bad/tag \
    "docker.io/example/sdkman-ci@$digest"; do
    if PUBLISH_IMAGE="$image" bash "$project_dir/.github/workflowes/scripts/publish-image.sh" > "$test_dir/output" 2>&1; then
        printf 'ERROR: accepted an image without a valid explicit tag\n' >&2
        exit 1
    fi
    if [[ -s "$PUSH_CALLS" ]]; then
        printf 'ERROR: pushed an image before validating its tag\n' >&2
        exit 1
    fi
done

: > "$PUSH_CALLS"
for summary in "$test_dir" "$test_dir/missing/summary"; do
    if GITHUB_STEP_SUMMARY="$summary" bash "$project_dir/.github/workflowes/scripts/publish-image.sh" > "$test_dir/output" 2>&1; then
        printf 'ERROR: accepted an unusable summary path\n' >&2
        exit 1
    fi
    if [[ -s "$PUSH_CALLS" ]]; then
        printf 'ERROR: pushed an image before checking the summary path\n' >&2
        exit 1
    fi
done

for PUSH_OUTPUT in '' 'layer: Pushed' \
    'v1.2.3: digest: sha256:bad size: 1234' \
    "other-tag: digest: $digest size: 1234" \
    "$digest_line"$'\n'"$digest_line"; do
    : > "$GITHUB_STEP_SUMMARY"
    if bash "$project_dir/.github/workflowes/scripts/publish-image.sh" > "$test_dir/output" 2>&1; then
        printf 'ERROR: accepted missing, invalid, or ambiguous digest\n' >&2
        exit 1
    fi
    [[ ! -s "$GITHUB_STEP_SUMMARY" ]]
done

# A failed push must fail even if its output contains a valid digest
PUSH_OUTPUT=$digest_line
PUSH_STATUS=7
if bash "$project_dir/.github/workflowes/scripts/publish-image.sh" > "$test_dir/output" 2>&1; then
    printf 'ERROR: accepted failed push\n' >&2
    exit 1
fi
[[ ! -s "$GITHUB_STEP_SUMMARY" ]]

printf 'Release image publishing checks passed\n'
