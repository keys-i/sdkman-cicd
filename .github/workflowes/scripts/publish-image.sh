#!/usr/bin/env bash
set -euo pipefail
export LC_ALL=C

: "${PUBLISH_IMAGE:?PUBLISH_IMAGE must name the tested release image}"
: "${GITHUB_STEP_SUMMARY:?GITHUB_STEP_SUMMARY must name the job summary file}"
if [[ "$PUBLISH_IMAGE" != *:* || "$PUBLISH_IMAGE" == *@* ]]; then
    printf 'PUBLISH_IMAGE must include an explicit image tag and no digest\n' >&2
    exit 1
fi
bash "$(dirname -- "${BASH_SOURCE[0]}")/validate-release-tag.sh" "${PUBLISH_IMAGE##*:}"
: >> "$GITHUB_STEP_SUMMARY"

push_log=$(mktemp)
trap 'rm -f -- "$push_log"' EXIT
docker image push "$PUBLISH_IMAGE" | tee "$push_log"

# Read this push's digest without resolving a tag that could have moved
digest=$(awk -v tag="${PUBLISH_IMAGE##*:}" \
    '$1 == tag ":" && $2 == "digest:" {print $3}' "$push_log")
if [[ ! $digest =~ ^sha256:[0-9a-f]{64}$ ]]; then
    printf 'ERROR: push completed without exactly one valid image digest; check the push log\n' >&2
    exit 1
fi

printf '### Published image\n\nTag:\n\n    %s\n\nPin in CI:\n\n    %s@%s\n' \
    "$PUBLISH_IMAGE" "${PUBLISH_IMAGE%:*}" "$digest" >> "$GITHUB_STEP_SUMMARY"
