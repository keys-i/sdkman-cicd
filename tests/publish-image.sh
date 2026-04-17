#!/usr/bin/env bash
set -euo pipefail

project_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
test_dir=$(mktemp -d)
trap 'rm -rf -- "$test_dir"' EXIT
export BASH_ENV=/dev/null
export PUBLISH_IMAGE=docker.io/example/sdkman-ci:v1.2.3
export GITHUB_STEP_SUMMARY="$test_dir/summary"
export PUSH_CALLS="$test_dir/push-calls"
export PUSH_OUTPUT PUSH_STATUS=0
printf -v digest 'sha256:%064d' 0
printf -v EXPECTED_IMAGE_ID 'sha256:%064d' 1
export EXPECTED_IMAGE_ID
export ACTUAL_IMAGE_ID="$EXPECTED_IMAGE_ID" INSPECT_STATUS=0
export EXPECTED_PUBLISHED_REF="docker.io/example/sdkman-ci@$digest"
export PULLED_IMAGE_ID="$EXPECTED_IMAGE_ID" PULL_STATUS=0 VERIFY_STATUS=0
digest_line="v1.2.3: digest: $digest size: 1234"

# Stub only Docker so these checks cannot publish an image
docker() {
    if [[ "$1 $2" == 'image inspect' ]]; then
        [[ $# == 5 && $3 == --format && $4 == '{{.Id}}' ]] || return 99
        if [[ $5 == "$EXPECTED_PUBLISHED_REF" ]]; then
            printf 'verify\n' >> "$PUSH_CALLS"
            [[ "$VERIFY_STATUS" == 0 ]] || return "$VERIFY_STATUS"
            printf '%s\n' "$PULLED_IMAGE_ID"
            return
        fi
        [[ $5 == "$PUBLISH_IMAGE" ]] || return 99
        printf 'inspect\n' >> "$PUSH_CALLS"
        [[ "$INSPECT_STATUS" == 0 ]] || return "$INSPECT_STATUS"
        printf '%s\n' "$ACTUAL_IMAGE_ID"
        return
    fi
    if [[ "$1 $2" == 'image pull' ]]; then
        [[ $# == 3 && $3 == "$EXPECTED_PUBLISHED_REF" ]] || return 99
        printf 'pull\n' >> "$PUSH_CALLS"
        return "$PULL_STATUS"
    fi
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
[[ $(cat "$PUSH_CALLS") == $'inspect\npush\npull\nverify' ]] || exit 1
successful_summary=$(cat "$GITHUB_STEP_SUMMARY")

: > "$PUSH_CALLS"
if EXPECTED_IMAGE_ID='' bash "$project_dir/.github/workflowes/scripts/publish-image.sh" > "$test_dir/output" 2>&1; then
    printf 'ERROR: accepted a missing tested image ID\n' >&2
    exit 1
fi
[[ ! -s "$PUSH_CALLS" ]]

for ACTUAL_IMAGE_ID in '' "$digest"; do
    : > "$PUSH_CALLS"
    if bash "$project_dir/.github/workflowes/scripts/publish-image.sh" > "$test_dir/output" 2>&1; then
        printf 'ERROR: accepted an image different from the tested image\n' >&2
        exit 1
    fi
    [[ $(cat "$PUSH_CALLS") == inspect ]]
    grep -Fq 'image differs from the tested image' "$test_dir/output"
done
ACTUAL_IMAGE_ID=$EXPECTED_IMAGE_ID
: > "$PUSH_CALLS"
status=0
INSPECT_STATUS=37 bash "$project_dir/.github/workflowes/scripts/publish-image.sh" > "$test_dir/output" 2>&1 || status=$?
[[ "$status" == 37 && $(cat "$PUSH_CALLS") == inspect ]]
[[ $(cat "$GITHUB_STEP_SUMMARY") == "$successful_summary" ]]

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
    : > "$PUSH_CALLS"
    if bash "$project_dir/.github/workflowes/scripts/publish-image.sh" > "$test_dir/output" 2>&1; then
        printf 'ERROR: accepted missing, invalid, or ambiguous digest\n' >&2
        exit 1
    fi
    [[ ! -s "$GITHUB_STEP_SUMMARY" ]]
    [[ $(cat "$PUSH_CALLS") == $'inspect\npush' ]] || exit 1
done

# A failed push must fail even if its output contains a valid digest
PUSH_OUTPUT=$digest_line
PUSH_STATUS=7
: > "$PUSH_CALLS"
if bash "$project_dir/.github/workflowes/scripts/publish-image.sh" > "$test_dir/output" 2>&1; then
    printf 'ERROR: accepted failed push\n' >&2
    exit 1
fi
[[ ! -s "$GITHUB_STEP_SUMMARY" ]]
[[ $(cat "$PUSH_CALLS") == $'inspect\npush' ]] || exit 1

PUSH_STATUS=0
for PULLED_IMAGE_ID in '' "$digest"; do
    : > "$PUSH_CALLS"
    status=0
    bash "$project_dir/.github/workflowes/scripts/publish-image.sh" > "$test_dir/output" 2>&1 || status=$?
    [[ $status == 1 && ! -s "$GITHUB_STEP_SUMMARY" ]] || exit 1
    [[ $(cat "$PUSH_CALLS") == $'inspect\npush\npull\nverify' ]] || exit 1
    grep -Fq 'published image differs from the tested image' "$test_dir/output"
done
PULLED_IMAGE_ID=$EXPECTED_IMAGE_ID

: > "$PUSH_CALLS"
status=0
PULL_STATUS=31 bash "$project_dir/.github/workflowes/scripts/publish-image.sh" > "$test_dir/output" 2>&1 || status=$?
[[ $status == 31 && ! -s "$GITHUB_STEP_SUMMARY" ]] || exit 1
[[ $(cat "$PUSH_CALLS") == $'inspect\npush\npull' ]] || exit 1

: > "$PUSH_CALLS"
status=0
VERIFY_STATUS=32 bash "$project_dir/.github/workflowes/scripts/publish-image.sh" > "$test_dir/output" 2>&1 || status=$?
[[ $status == 32 && ! -s "$GITHUB_STEP_SUMMARY" ]] || exit 1
[[ $(cat "$PUSH_CALLS") == $'inspect\npush\npull\nverify' ]] || exit 1

printf 'Release image publishing checks passed\n'
