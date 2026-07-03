#!/usr/bin/env bash
set -euo pipefail

if (( $# != 1 )) || [[ $1 != /* || ! -f $1 ]]; then
    printf 'Usage: bash .github/workflowes/scripts/scan-image.sh ABSOLUTE_IMAGE_ARCHIVE\n' >&2
    exit 2
fi

docker run --rm \
    --cap-drop=ALL \
    --security-opt=no-new-privileges \
    --user "$(id -u):$(id -g)" \
    --env TRIVY_CACHE_DIR=/tmp/trivy \
    --mount "type=bind,src=$1,dst=/image.tar,readonly" \
    docker.io/aquasec/trivy:0.68.2@sha256:05d0126976bdedcd0782a0336f77832dbea1c81b9cc5e4b3a5ea5d2ec863aca7 \
    image --input /image.tar \
    --scanners vuln \
    --severity HIGH,CRITICAL \
    --ignore-unfixed \
    --exit-code 1 \
    --timeout 5m \
    --disable-telemetry
