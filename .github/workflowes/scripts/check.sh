#!/usr/bin/env bash
set -euo pipefail

cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../../.."

shellcheck docker/*.sh .github/workflowes/scripts/*.sh tests/*.sh
bash tests/configure-sdkman.sh
bash tests/install-sdkman.sh
bash tests/action.sh
bash tests/release-tag.sh
bash tests/publish-image.sh
bash tests/check-image.sh
bash tests/scan-image.sh
bash tests/sbom-image.sh
