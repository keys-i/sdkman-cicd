#!/usr/bin/env bash
set -euo pipefail
export LC_ALL=C

if (( $# != 1 )) || [[ ! $1 =~ ^[A-Za-z0-9_][A-Za-z0-9_.-]{0,127}$ ]]; then
    printf 'Expected one Docker-compatible release tag: 1-128 ASCII letters, digits, underscores, dots, or hyphens; start with a letter, digit, or underscore\n' >&2
    exit 1
fi
