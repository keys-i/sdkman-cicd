#!/usr/bin/env bash
set -euo pipefail

cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../../.."

docker run --rm --network none \
    --mount "type=bind,src=$PWD/.github/workflows,dst=/repo/.github/workflows,readonly" \
    --mount "type=bind,src=$PWD/examples,dst=/repo/examples,readonly" \
    --workdir /repo \
    docker.io/rhysd/actionlint:1.7.7@sha256:887a259a5a534f3c4f36cb02dca341673c6089431057242cdc931e9f133147e9 \
    -color .github/workflows/*.yml examples/github-actions.yml
