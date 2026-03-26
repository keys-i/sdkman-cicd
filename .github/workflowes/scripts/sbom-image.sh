#!/usr/bin/env bash
set -euo pipefail

if (( $# != 1 )) || [[ $1 != /* || ! -f $1 ]]; then
    printf 'Usage: bash .github/workflowes/scripts/sbom-image.sh ABSOLUTE_IMAGE_ARCHIVE\n' >&2
    exit 2
fi

docker run --rm \
    --mount "type=bind,src=$1,dst=/image.tar,readonly" \
    docker.io/aquasec/trivy:0.68.2@sha256:05d0126976bdedcd0782a0336f77832dbea1c81b9cc5e4b3a5ea5d2ec863aca7 \
    image --input /image.tar \
    --format cyclonedx \
    --timeout 5m \
    --disable-telemetry
