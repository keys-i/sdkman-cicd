#!/usr/bin/env bash
set -euo pipefail

project_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
test_dir=$(mktemp -d)
trap 'rm -rf -- "$test_dir"' EXIT
export BASH_ENV=/dev/null
export SBOM_CALLS="$test_dir/calls" SBOM_STATUS=0
printf -v image_id 'sha256:%064d' 1
valid_sbom=$(jq -n --arg image_id "$image_id" '{
    bomFormat: "CycloneDX",
    metadata: {component: {type: "container", properties: [
        {name: "aquasecurity:trivy:ImageID", value: $image_id}
    ]}},
    components: [{type: "library", name: "bash", version: "5.2"}]
}')
export SBOM_OUTPUT="$valid_sbom"
archive="$test_dir/release image.tar"
touch "$archive"

# Stub Docker to check output handling without downloading an image
docker() {
    printf '%s\n' "$@" > "$SBOM_CALLS"
    printf '%s\n' "$SBOM_OUTPUT"
    printf 'Generator diagnostics\n' >&2
    return "$SBOM_STATUS"
}
export -f docker

for SBOM_STATUS in 0 23; do
    status=0
    bash "$project_dir/.github/workflowes/scripts/sbom-image.sh" "$archive" "$image_id" > "$test_dir/sbom.json" 2> "$test_dir/errors" || status=$?
    [[ $status == "$SBOM_STATUS" ]] || exit 1
    if (( status == 0 )); then
        [[ $(cat "$test_dir/sbom.json") == "$valid_sbom" ]] || exit 1
    else
        [[ ! -s "$test_dir/sbom.json" ]] || exit 1
    fi
    grep -Fxq 'Generator diagnostics' "$test_dir/errors"
    grep -Fxq "type=bind,src=$archive,dst=/image.tar,readonly" "$SBOM_CALLS"
    args=$(cat "$SBOM_CALLS")
    [[ $args == $'run\n--rm\n--cap-drop=ALL\n--security-opt=no-new-privileges\n--user\n'* ]] || exit 1
    [[ $args == *$'--user\n'"$(id -u):$(id -g)"$'\n--env\nTRIVY_CACHE_DIR=/tmp/trivy\n--mount\n'* ]] || exit 1
    [[ $args == *$'--input\n/image.tar\n'* && $args == *$'--format\ncyclonedx\n'* ]] || exit 1
done

SBOM_STATUS=0
for filter in '.bomFormat = "SPDX"' '.components = []' '.components = {}' \
    '.metadata.component.type = "library"' '.metadata.component.properties = []' \
    '.metadata.component.properties[0].value = "sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"' \
    '.metadata.component.properties += [.metadata.component.properties[0]]'; do
    jq "$filter" <<< "$valid_sbom" > "$test_dir/invalid.json"
    SBOM_OUTPUT=$(cat "$test_dir/invalid.json")
    status=0
    bash "$project_dir/.github/workflowes/scripts/sbom-image.sh" "$archive" "$image_id" > "$test_dir/sbom.json" 2> "$test_dir/errors" || status=$?
    [[ $status == 1 && ! -s "$test_dir/sbom.json" ]] || exit 1
done
for SBOM_OUTPUT in '' 'not JSON' '{}' "{} $valid_sbom"; do
    status=0
    bash "$project_dir/.github/workflowes/scripts/sbom-image.sh" "$archive" "$image_id" > "$test_dir/sbom.json" 2> "$test_dir/errors" || status=$?
    [[ $status == 1 && ! -s "$test_dir/sbom.json" ]] || exit 1
done

: > "$SBOM_CALLS"
for invalid in '' relative.tar "$test_dir/missing.tar" "$test_dir"; do
    status=0
    bash "$project_dir/.github/workflowes/scripts/sbom-image.sh" "$invalid" "$image_id" > "$test_dir/output" 2>&1 || status=$?
    [[ $status == 2 && ! -s $SBOM_CALLS ]] || exit 1
done
for invalid in '' 'sha256:bad' "$image_id"$'\n'; do
    status=0
    bash "$project_dir/.github/workflowes/scripts/sbom-image.sh" "$archive" "$invalid" > "$test_dir/output" 2>&1 || status=$?
    [[ $status == 2 && ! -s $SBOM_CALLS ]] || exit 1
done
status=0
bash "$project_dir/.github/workflowes/scripts/sbom-image.sh" > "$test_dir/output" 2>&1 || status=$?
[[ $status == 2 && ! -s $SBOM_CALLS ]] || exit 1
status=0
bash "$project_dir/.github/workflowes/scripts/sbom-image.sh" "$archive" > "$test_dir/output" 2>&1 || status=$?
[[ $status == 2 && ! -s $SBOM_CALLS ]] || exit 1
status=0
bash "$project_dir/.github/workflowes/scripts/sbom-image.sh" "$archive" "$image_id" extra > "$test_dir/output" 2>&1 || status=$?
[[ $status == 2 && ! -s $SBOM_CALLS ]] || exit 1

printf 'Release SBOM checks passed\n'
