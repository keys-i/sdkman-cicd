#!/usr/bin/env bash
set -euo pipefail

if (( $# != 1 )) || [[ -z $1 || $1 == -* ]]; then
    printf 'Usage: bash scripts/check-image.sh IMAGE\n' >&2
    exit 2
fi
image=$1
cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.."

docker run --rm --network none \
    --mount "type=bind,src=$PWD/tests,dst=/tests,readonly" \
    --pull=never "$image" bash /tests/smoke.sh

docker run --rm --network none \
    --mount "type=bind,src=$PWD/tests,dst=/tests,readonly" \
    --user 0 --pull=never "$image" bash /tests/smoke.sh

cache_volume=$(docker volume create)
cleanup() {
    local status=$?
    docker volume rm "$cache_volume" || exit 1
    exit "$status"
}
trap cleanup EXIT

for mode in install cached; do
    network=none
    if [[ "$mode" == install ]]; then network=bridge; fi
    docker run --rm --network "$network" \
        --mount "type=volume,src=$cache_volume,dst=/workspace" \
        --mount "type=bind,src=$PWD/tests,dst=/tests,readonly" \
        --env SDKMAN_CANDIDATES_DIR=/workspace/candidates \
        --workdir /tests \
        --pull=never "$image" bash /tests/integration.sh "$mode"
done
