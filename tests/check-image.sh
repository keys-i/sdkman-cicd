#!/usr/bin/env bash
set -euo pipefail

project_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
test_dir=$(mktemp -d)
trap 'rm -rf -- "$test_dir"' EXIT
export BASH_ENV=/dev/null
export IMAGE_CHECK_CALLS="$test_dir/calls"
export IMAGE_CHECK_TESTS="$project_dir/tests"
export IMAGE_CHECK_FAIL=''

# Intercept every Docker call so these checks need no daemon or downloads
docker() {
    local step network
    case "$1 $2" in
        'run --rm')
            step=${*: -1}
            network=none
            if [[ "$step" == /tests/smoke.sh ]]; then
                step=smoke
                [[ "${*: -4:1}" == --pull=never ]] || return 99
                [[ "${*: -3:1}" == sdkman-ci:check ]] || return 99
                [[ "$6" == "type=bind,src=$IMAGE_CHECK_TESTS,dst=/tests,readonly" ]] || return 99
            else
                [[ "$step" == install || "$step" == cached ]] || return 99
                if [[ "$step" == install ]]; then network=bridge; fi
                [[ "$6" == type=volume,src=check-volume,dst=/workspace ]] || return 99
                [[ "$8" == "type=bind,src=$IMAGE_CHECK_TESTS,dst=/tests,readonly" ]] || return 99
                [[ "${10}" == SDKMAN_CANDIDATES_DIR=/workspace/candidates ]] || return 99
                [[ "${12}" == /tests && "${13}" == --pull=never ]] || return 99
                [[ "${14}" == sdkman-ci:check ]] || return 99
                [[ "${15}" == bash && "${16}" == /tests/integration.sh ]] || return 99
            fi
            [[ "$3" == --network && "$4" == "$network" ]] || return 99
            ;;
        'volume create')
            [[ $# == 2 ]] || return 99
            step=create
            ;;
        'volume rm')
            [[ $# == 3 && "$3" == check-volume ]] || return 99
            step=cleanup
            ;;
        *) return 99 ;;
    esac
    printf '%s\n' "$step" >> "$IMAGE_CHECK_CALLS"
    [[ "$step" != "$IMAGE_CHECK_FAIL" ]] || return 37
    if [[ "$step" == create ]]; then printf 'check-volume\n'; fi
}
export -f docker

# Exercise invocation outside the repository as well as failure cleanup
cd "$test_dir"
for IMAGE_CHECK_FAIL in '' smoke create install cached cleanup; do
    : > "$IMAGE_CHECK_CALLS"
    status=0
    bash "$project_dir/scripts/check-image.sh" sdkman-ci:check > "$test_dir/output" 2>&1 || status=$?
    case "$IMAGE_CHECK_FAIL" in
        '') expected_status=0; expected=$'smoke\ncreate\ninstall\ncached\ncleanup' ;;
        smoke) expected_status=37; expected=smoke ;;
        create) expected_status=37; expected=$'smoke\ncreate' ;;
        install) expected_status=37; expected=$'smoke\ncreate\ninstall\ncleanup' ;;
        cached) expected_status=37; expected=$'smoke\ncreate\ninstall\ncached\ncleanup' ;;
        cleanup) expected_status=1; expected=$'smoke\ncreate\ninstall\ncached\ncleanup' ;;
    esac
    [[ "$status" == "$expected_status" ]]
    [[ $(cat "$IMAGE_CHECK_CALLS") == "$expected" ]]
done

: > "$IMAGE_CHECK_CALLS"
check_usage() {
    local status=0
    bash "$project_dir/scripts/check-image.sh" "$@" > "$test_dir/output" 2>&1 || status=$?
    [[ "$status" == 2 && ! -s "$IMAGE_CHECK_CALLS" ]]
}
check_usage
check_usage ''
check_usage --privileged
check_usage sdkman-ci:check unexpected

printf 'Image check orchestration checks passed\n'
