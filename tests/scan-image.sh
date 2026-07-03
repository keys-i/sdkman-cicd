#!/usr/bin/env bash
set -euo pipefail

project_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
test_dir=$(mktemp -d)
trap 'rm -rf -- "$test_dir"' EXIT
export BASH_ENV=/dev/null
export SCAN_CALLS="$test_dir/calls" SCAN_STATUS=0
archive="$test_dir/release image.tar"
touch "$archive"

# Stub Docker so these checks cannot download or scan an image
docker() {
    printf '%s\n' "$@" > "$SCAN_CALLS"
    printf 'Scan findings\n'
    printf 'Scanner diagnostics\n' >&2
    return "$SCAN_STATUS"
}
export -f docker

for SCAN_STATUS in 0 1 23; do
    status=0
    bash "$project_dir/.github/workflowes/scripts/scan-image.sh" "$archive" 2>&1 | tee "$test_dir/report" > "$test_dir/console" || status=$?
    [[ $status == "$SCAN_STATUS" ]] || exit 1
    [[ $(cat "$test_dir/report") == $'Scan findings\nScanner diagnostics' ]] || exit 1
    cmp "$test_dir/report" "$test_dir/console"
    grep -Fxq "type=bind,src=$archive,dst=/image.tar,readonly" "$SCAN_CALLS"
    grep -Fxq -- '--ignore-unfixed' "$SCAN_CALLS"
    grep -Fxq -- '--disable-telemetry' "$SCAN_CALLS"
    args=$(cat "$SCAN_CALLS")
    [[ $args == $'run\n--rm\n--cap-drop=ALL\n--security-opt=no-new-privileges\n--user\n'* ]] || exit 1
    [[ $args == *$'--user\n'"$(id -u):$(id -g)"$'\n--env\nTRIVY_CACHE_DIR=/tmp/trivy\n--mount\n'* ]] || exit 1
    [[ $args == *$'--input\n/image.tar\n'* &&
       $args == *$'--scanners\nvuln\n'* &&
       $args == *$'--severity\nHIGH,CRITICAL\n'* &&
       $args == *$'--exit-code\n1\n'* ]] || exit 1
done

status=0
SCAN_STATUS=0 bash "$project_dir/.github/workflowes/scripts/scan-image.sh" "$archive" 2>&1 | tee "$test_dir" > /dev/null 2>&1 || status=$?
[[ $status != 0 ]] || exit 1

: > "$SCAN_CALLS"
for invalid in '' relative.tar "$test_dir/missing.tar" "$test_dir"; do
    status=0
    bash "$project_dir/.github/workflowes/scripts/scan-image.sh" "$invalid" > "$test_dir/output" 2>&1 || status=$?
    [[ $status == 2 && ! -s $SCAN_CALLS ]] || exit 1
done
status=0
bash "$project_dir/.github/workflowes/scripts/scan-image.sh" > "$test_dir/output" 2>&1 || status=$?
[[ $status == 2 && ! -s $SCAN_CALLS ]] || exit 1
status=0
bash "$project_dir/.github/workflowes/scripts/scan-image.sh" "$archive" extra > "$test_dir/output" 2>&1 || status=$?
[[ $status == 2 && ! -s $SCAN_CALLS ]] || exit 1

printf 'Release image scan checks passed\n'
