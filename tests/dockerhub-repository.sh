#!/usr/bin/env bash
set -euo pipefail

project_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
validator="$project_dir/.github/workflowes/scripts/validate-dockerhub-repository.sh"
printf -v longest_repository 'team/%250s' ''
longest_repository=${longest_repository// /a}

for repository in team/sdkman-ci your-org/sdkman_ci team/sdkman__ci team/sdkman--ci \
    team/ci2024 "$longest_repository"; do
    bash "$validator" "$repository"
done

for repository in '' sdkman-ci /sdkman-ci team/ team/a Team/sdkman-ci team/SDKMAN-CI \
    docker.io/team/sdkman-ci https://docker.io/team/sdkman-ci team/sdkman-ci:latest \
    team/sdkman-ci@sha256:abc team/sub/repo 'team/sdkman ci' ' team/sdkman-ci' \
    'team/sdkman-ci ' $'team/sdkman-ci\n' $'team/sdkman-ci\r' team/sdkman-é \
    team/.sdkman team/sdkman.ci team/-sdkman team/sdkman- team/sdkman___ci \
    team/sdkman_-ci -team/sdkman-ci team-/sdkman-ci 'team/sdkman;exit 0' \
    "${longest_repository}a"; do
    if bash "$validator" "$repository" > /dev/null 2>&1; then
        printf 'ERROR: accepted invalid Docker Hub repository: %q\n' "$repository" >&2
        exit 1
    fi
done

if bash "$validator" > /dev/null 2>&1; then
    printf 'ERROR: accepted a missing repository\n' >&2
    exit 1
fi
if bash "$validator" team/sdkman-ci extra > /dev/null 2>&1; then
    printf 'ERROR: accepted extra arguments\n' >&2
    exit 1
fi

printf 'Docker Hub repository validation checks passed\n'
