#!/usr/bin/env bash
set -euo pipefail

project_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
test_dir=$(mktemp -d)
test_dir=$(cd -- "$test_dir" && pwd -P)
trap 'rm -rf -- "$test_dir"' EXIT
export BASH_ENV=/dev/null RUNNER_OS=Linux
export GITHUB_WORKSPACE="$test_dir/workspace" RUNNER_TEMP="$test_dir/temp"
export GITHUB_OUTPUT="$test_dir/output" SDKMAN_WORKING_DIRECTORY='app with spaces'
export SDKMAN_CACHE=true SDKMAN_RUN=true
export ACTION_CALLS="$test_dir/calls"
mkdir -p "$GITHUB_WORKSPACE/$SDKMAN_WORKING_DIRECTORY" "$RUNNER_TEMP"
printf 'java=21.0.12.1-tem\n' > "$GITHUB_WORKSPACE/$SDKMAN_WORKING_DIRECTORY/.sdkmanrc"

# Supply Linux OS metadata when these offline checks run on macOS
sha256sum() {
    if [[ $1 == /etc/os-release ]]; then
        printf '%064d  /etc/os-release\n' 0
    else
        shasum -a 256 "$@"
    fi
}
export -f sha256sum
prepare="$project_dir/.github/workflowes/scripts/prepare-action.sh"
bash "$prepare"
sdkman_path=$(sed -n 's/^sdkman-dir=//p' "$GITHUB_OUTPUT")
[[ ! -e "$sdkman_path" && -d ${sdkman_path%/*} ]] || exit 1
grep -Fxq "working-directory=$GITHUB_WORKSPACE/$SDKMAN_WORKING_DIRECTORY" "$GITHUB_OUTPUT"
grep -Fxq "candidates-dir=$RUNNER_TEMP/sdkman-ci-candidates" "$GITHUB_OUTPUT"
grep -Eq '^rc-hash=[0-9a-f]{64}$' "$GITHUB_OUTPUT"

for scenario in unsupported-os invalid-cache missing-rc outside-workspace empty-command; do
    : > "$GITHUB_OUTPUT"
    case "$scenario" in
        unsupported-os) override=RUNNER_OS=Windows ;;
        invalid-cache) override=SDKMAN_CACHE=maybe ;;
        missing-rc) override=SDKMAN_WORKING_DIRECTORY=. ;;
        outside-workspace) override=SDKMAN_WORKING_DIRECTORY=.. ;;
        empty-command) override=SDKMAN_RUN= ;;
    esac
    if env "$override" bash "$prepare" > "$test_dir/error" 2>&1; then
        printf 'ERROR: action accepted %s\n' "$scenario" >&2
        exit 1
    fi
    [[ ! -s "$GITHUB_OUTPUT" ]] || exit 1
done

export SDKMAN_DIR="$test_dir/sdkman"
mkdir -p "$SDKMAN_DIR/bin"
export ACTION_READY="$test_dir/ready" ACTION_SCENARIO
cat > "$SDKMAN_DIR/bin/sdkman-init.sh" <<'INIT'
sdk() {
    printf '%s\n' "$*" >> "$ACTION_CALLS"
    case "$*" in
        env)
            [[ -f "$ACTION_READY" ]] || return 1
            export JAVA_HOME=/selected/java
            ;;
        'env install')
            [[ "$ACTION_SCENARIO" != install-failure ]] || return 37
            [[ "$ACTION_SCENARIO" == activation-failure ]] || : > "$ACTION_READY"
            ;;
        *) return 99 ;;
    esac
}
INIT
SDKMAN_RUN=$(cat <<'COMMAND'
[[ "$JAVA_HOME" == /selected/java ]]
printf 'build\n' >> "$ACTION_CALLS"
COMMAND
)
export SDKMAN_RUN
for ACTION_SCENARIO in fresh cached install-failure activation-failure build-failure; do
    : > "$ACTION_CALLS"
    rm -f -- "$ACTION_READY"
    expected_status=0
    expected_calls=$'env\nenv install\nenv\nbuild'
    case "$ACTION_SCENARIO" in
        cached) : > "$ACTION_READY"; expected_calls=$'env\nenv\nbuild' ;;
        install-failure) expected_status=37; expected_calls=$'env\nenv install' ;;
        activation-failure) expected_status=1; expected_calls=$'env\nenv install\nenv' ;;
        build-failure)
            export SDKMAN_RUN='exit 42'
            expected_status=42
            expected_calls=$'env\nenv install\nenv'
            ;;
    esac
    status=0
    bash "$project_dir/.github/workflowes/scripts/run-action.sh" || status=$?
    [[ $status == "$expected_status" && $(cat "$ACTION_CALLS") == "$expected_calls" ]] || exit 1
done
printf 'Marketplace action checks passed\n'
