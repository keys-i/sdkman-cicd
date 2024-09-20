#!/usr/bin/env bash
set -e -o pipefail

sdkman_init="${SDKMAN_DIR:?SDKMAN_DIR must name the SDKMAN installation}/bin/sdkman-init.sh"

# Honor cache overrides before SDKMAN restores candidate homes and PATH
old_assignment="export SDKMAN_CANDIDATES_DIR=\"\${SDKMAN_DIR}/candidates\""
new_assignment="export SDKMAN_CANDIDATES_DIR=\"\${SDKMAN_CANDIDATES_DIR:-\${SDKMAN_DIR}/candidates}\""
sed "s|^$old_assignment\$|$new_assignment|" "$sdkman_init" > "$sdkman_init.tmp"
if ! grep -Fxq "$new_assignment" "$sdkman_init.tmp"; then
    printf 'ERROR: SDKMAN initializer changed; review candidate cache support\n' >&2
    exit 1
fi
mv "$sdkman_init.tmp" "$sdkman_init"

# Configure CI without relying on the installer's newer CI mode
printf '\n%s\n' \
    sdkman_auto_answer=true \
    sdkman_colour_enable=false \
    sdkman_selfupdate_feature=false \
    sdkman_checksum_enable=true \
    sdkman_auto_complete=false \
    sdkman_auto_env=false \
    sdkman_healthcheck_enable=false >> "$SDKMAN_DIR/etc/config"
