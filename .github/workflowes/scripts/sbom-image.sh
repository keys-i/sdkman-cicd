#!/usr/bin/env bash
set -euo pipefail

if (( $# != 2 )) || [[ $1 != /* || ! -f $1 || ! $2 =~ ^sha256:[0-9a-f]{64}$ ]]; then
    printf 'Usage: bash .github/workflowes/scripts/sbom-image.sh ABSOLUTE_IMAGE_ARCHIVE EXPECTED_IMAGE_ID\n' >&2
    exit 2
fi

sbom=$(mktemp)
trap 'rm -f -- "$sbom"' EXIT

docker run --rm \
    --mount "type=bind,src=$1,dst=/image.tar,readonly" \
    docker.io/aquasec/trivy:0.68.2@sha256:05d0126976bdedcd0782a0336f77832dbea1c81b9cc5e4b3a5ea5d2ec863aca7 \
    image --input /image.tar \
    --format cyclonedx \
    --timeout 5m \
    --disable-telemetry > "$sbom"

if ! jq --slurp --exit-status --arg image_id "$2" '
    length == 1 and (.[0] |
        .bomFormat == "CycloneDX" and
        .metadata.component.type == "container" and
        ([.metadata.component.properties[]? |
            select(.name == "aquasecurity:trivy:ImageID") | .value] == [$image_id]) and
        (.components | type == "array" and length > 0)
    )
' "$sbom" > /dev/null; then
    printf 'ERROR: SBOM must contain components and identify the tested container image\n' >&2
    exit 1
fi

cat -- "$sbom"
