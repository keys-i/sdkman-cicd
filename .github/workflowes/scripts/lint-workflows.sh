#!/usr/bin/env bash
set -euo pipefail

cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../../.."

docker run --rm --network none \
    --cap-drop=ALL \
    --security-opt=no-new-privileges \
    --user "$(id -u):$(id -g)" \
    --mount "type=bind,src=$PWD/.github/workflows,dst=/repo/.github/workflows,readonly" \
    --mount "type=bind,src=$PWD/examples,dst=/repo/examples,readonly" \
    --workdir /repo \
    docker.io/rhysd/actionlint:1.7.8@sha256:96d4a8c87dbbfb3bdd324f8fdc285fc3df5261e2decc619a4dd7e8ee52bbfd46 \
    -color .github/workflows/*.yml examples/github-actions.yml
