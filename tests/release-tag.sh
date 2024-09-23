#!/usr/bin/env bash
set -euo pipefail

project_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
validator="$project_dir/scripts/validate-release-tag.sh"
printf -v longest_tag '%128s' ''
longest_tag=${longest_tag// /a}

for tag in a 0 V1.2.3 v1.2.3 v1.2.3-rc.1 2024.09.23 _snapshot "$longest_tag"; do
    bash "$validator" "$tag"
done

for tag in '' '.1.2.3' '-1.2.3' 'release/v1.2.3' 'v1.2.3+build.1' \
    'v1.2.3 rc1' ' v1.2.3' 'v1.2.3 ' $'v1.2.3\n' $'v1.2.3\r' \
    'v1.2.3;exit 0' "\$(exit 0)" 'v1.2.3-é' "${longest_tag}a"; do
    if bash "$validator" "$tag" > /dev/null 2>&1; then
        printf 'ERROR: accepted invalid tag: %q\n' "$tag" >&2
        exit 1
    fi
done

if bash "$validator" > /dev/null 2>&1; then
    printf 'ERROR: accepted a missing tag\n' >&2
    exit 1
fi
if bash "$validator" v1.2.3 extra > /dev/null 2>&1; then
    printf 'ERROR: accepted extra arguments\n' >&2
    exit 1
fi

printf 'Release tag validation checks passed\n'
