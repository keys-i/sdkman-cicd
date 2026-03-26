#!/usr/bin/env bash
set -euo pipefail

project_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
test_dir=$(mktemp -d)
trap 'rm -rf -- "$test_dir"' EXIT
export BASH_ENV=/dev/null
export SBOM_CALLS="$test_dir/calls" SBOM_STATUS=0
archive="$test_dir/release image.tar"
touch "$archive"

# Stub Docker to check output handling without downloading an image
docker() {
    printf '%s\n' "$@" > "$SBOM_CALLS"
    printf '{"bomFormat":"CycloneDX"}\n'
    printf 'Generator diagnostics\n' >&2
    return "$SBOM_STATUS"
}
export -f docker

for SBOM_STATUS in 0 23; do
    status=0
    bash "$project_dir/.github/workflowes/scripts/sbom-image.sh" "$archive" > "$test_dir/sbom.json" 2> "$test_dir/errors" || status=$?
    [[ $status == "$SBOM_STATUS" ]] || exit 1
    [[ $(cat "$test_dir/sbom.json") == '{"bomFormat":"CycloneDX"}' ]] || exit 1
    grep -Fxq 'Generator diagnostics' "$test_dir/errors"
    grep -Fxq "type=bind,src=$archive,dst=/image.tar,readonly" "$SBOM_CALLS"
    args=$(cat "$SBOM_CALLS")
    [[ $args == *$'--input\n/image.tar\n'* && $args == *$'--format\ncyclonedx\n'* ]] || exit 1
done

: > "$SBOM_CALLS"
for invalid in '' relative.tar "$test_dir/missing.tar" "$test_dir"; do
    status=0
    bash "$project_dir/.github/workflowes/scripts/sbom-image.sh" "$invalid" > "$test_dir/output" 2>&1 || status=$?
    [[ $status == 2 && ! -s $SBOM_CALLS ]] || exit 1
done
status=0
bash "$project_dir/.github/workflowes/scripts/sbom-image.sh" > "$test_dir/output" 2>&1 || status=$?
[[ $status == 2 && ! -s $SBOM_CALLS ]] || exit 1
status=0
bash "$project_dir/.github/workflowes/scripts/sbom-image.sh" "$archive" extra > "$test_dir/output" 2>&1 || status=$?
[[ $status == 2 && ! -s $SBOM_CALLS ]] || exit 1

printf 'Release SBOM checks passed\n'
