#!/usr/bin/env bash
set -euo pipefail
export LC_ALL=C

component='[a-z0-9]+((_|__|-+)[a-z0-9]+)*'
if (( $# != 1 )) || [[ ! $1 =~ ^${component}/${component}$ ]] \
    || (( ${#1} > 255 )) || [[ ${1#*/} != ??* ]]; then
    printf 'Expected Docker Hub namespace/repository: lowercase letters, digits, hyphens, or underscores; no hostname, tag, or digest; repository at least 2 characters, full path at most 255\n' >&2
    exit 1
fi
