#!/usr/bin/env bash
set -euo pipefail

if (( $# != 1 )) || [[ -z $1 || $1 == -* ]]; then
    printf 'Usage: bash .github/workflowes/scripts/check-image.sh IMAGE\n' >&2
    exit 2
fi
image=$1
cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../../.."

if [[ -n ${EXPECTED_PLATFORM:-} ]]; then
    actual_platform=$(docker image inspect --format '{{.Os}}/{{.Architecture}}' "$image")
    if [[ "$actual_platform" != "$EXPECTED_PLATFORM" ]]; then
        printf 'ERROR: expected image platform %s, found %s\n' "$EXPECTED_PLATFORM" "$actual_platform" >&2
        exit 1
    fi
fi

docker run --rm --network none \
    --mount "type=bind,src=$PWD/tests,dst=/tests,readonly" \
    --pull=never "$image" bash /tests/smoke.sh 1000

docker run --rm --network none \
    --mount "type=bind,src=$PWD/tests,dst=/tests,readonly" \
    --user 0 --pull=never "$image" bash /tests/smoke.sh 0

cache_volume=$(docker volume create)
cleanup() {
    local status=$?
    if ! docker volume rm "$cache_volume" && (( status == 0 )); then
        status=1
    fi
    exit "$status"
}
trap cleanup EXIT

for mode in install cached; do
    network=none
    cache_mount=/restored-workspace
    if [[ "$mode" == install ]]; then
        network=bridge
        cache_mount=/workspace
    fi
    for fixture_dir in /tests /tests/java17; do
        docker run --rm --network "$network" \
            --mount "type=volume,src=$cache_volume,dst=$cache_mount" \
            --mount "type=bind,src=$PWD/tests,dst=/tests,readonly" \
            --env "SDKMAN_CANDIDATES_DIR=$cache_mount/candidates" \
            --workdir "$fixture_dir" \
            --pull=never "$image" bash /tests/integration.sh "$mode"
    done
done
