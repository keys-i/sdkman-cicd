# SDKMAN CI image

Keep Java and other SDK versions in your application's `.sdkmanrc`. This image
provides SDKMAN and its download tools, without a preinstalled JDK. It is a CI
build environment, not an application runtime image.

## Build and check locally

```sh
docker build --tag sdkman-ci:local .
docker run --rm --network none \
  --mount "type=bind,src=$PWD/tests,dst=/tests,readonly" \
  sdkman-ci:local bash /tests/smoke.sh
```

The offline smoke test checks Bash initialization, a custom candidate directory,
cached Java and Kotlin activation through `.sdkmanrc`, and rejection of missing
versions or a missing `.sdkmanrc`. It uses empty SDK directories to test path
selection; it does not download or execute a real JDK or Kotlin compiler.

To exercise actual SDK installation and compilation, run this block from the
image repository after building `sdkman-ci:local`:

```sh
cache_volume=$(docker volume create)
(
  trap 'docker volume rm "$cache_volume"' EXIT
  for mode in install cached; do
    network=none
    if [ "$mode" = install ]; then network=bridge; fi
    docker run --rm --network "$network" \
      --mount "type=volume,src=$cache_volume,dst=/workspace" \
      --mount "type=bind,src=$PWD/tests,dst=/tests,readonly" \
      --env SDKMAN_CANDIDATES_DIR=/workspace/candidates \
      --workdir /tests \
      sdkman-ci:local bash /tests/integration.sh "$mode" || exit
  done
)
```

The first container installs the versions in `tests/.sdkmanrc` and compiles and
runs Java and Kotlin programs. The second container repeats the test with the
same candidates cache and networking disabled, using `sdk env` without attempting
installation. Each container has fresh SDKMAN state,
so this also checks that caching only the candidates directory is sufficient.
The temporary volume inherits the image's writable `/workspace` ownership and
is removed when the block finishes. Initial installation requires internet access.

## Run a project

In your application's repository, create `.sdkmanrc` with exact SDKMAN candidate
versions. Generate an initial file using `sdk env init`, or use this format with
versions available for your runner architecture:

```ini
java=21.0.4-tem
kotlin=2.0.20
```

These are example versions, not recommendations for current releases. Choose
versions with `sdk list java` and `sdk list kotlin`. Kotlin is optional; the image
supports other SDKMAN candidates too.

Run from the application's root directory:

```sh
docker run --rm \
  --mount "type=bind,src=$PWD,dst=/workspace" \
  sdkman-ci:local bash -c 'sdk env install && bash -c "sdk env && ./gradlew test"'
```

Replace `./gradlew test` with your build command. Start a fresh Bash shell after
installation to load newly installed candidate paths, then keep activation and
the build in that same shell. The `&&` chain prevents a build from starting when
installation or activation fails.

The image loads SDKMAN automatically for non-interactive Bash through `BASH_ENV`
and for the default user's interactive Bash through `.bashrc`. CI runners must
use **Bash**, not `sh`; no custom entrypoint is required. Initialize SDKMAN before
enabling `set -u`, and leave nounset disabled while calling `sdk`: upstream shell
code uses optional variables that may be unset.

## Cache candidates

Set `SDKMAN_CANDIDATES_DIR` to an absolute, writable path inside the container.
For platforms that only cache files under the project directory:

```sh
docker run --rm \
  --mount "type=bind,src=$PWD,dst=/workspace" \
  --env SDKMAN_CANDIDATES_DIR=/workspace/.cache/sdkman/candidates \
  sdkman-ci:local bash -c 'sdk env install && bash -c "sdk env && ./gradlew test"'
```

Configure your CI platform to restore `.cache/sdkman/candidates` before that
command and save it after a successful job. Include the OS, architecture, image
release, and a hash of `.sdkmanrc` in the cache key. Keep caches separate across
trust boundaries, such as untrusted pull requests and release jobs. Cache only
the candidates directory, not all of `/opt/sdkman`, which would overwrite the
image's CLI and configuration. Exclude the cache from source control.

For an entirely offline job with all required candidates already cached, use
`sdk env && ./gradlew test`. `sdk env install` may still contact the SDKMAN API to
validate versions even when their binaries are cached.

SDKMAN's initializer currently assigns its candidate path unconditionally. The
build applies a small checked change to honor `SDKMAN_CANDIDATES_DIR` before
restoring `JAVA_HOME`, other candidate homes, and `PATH`. If that upstream code
changes, the build fails with a request to review the compatibility change.

The image runs as user `sdkman` (UID/GID 1000). Mounted workspaces and caches must
be writable by that user. If a runner requires root, configure it to run the
container with `--user 0`; account for the resulting file ownership on the host.

## GitHub Actions application example

Copy [the example workflow](examples/github-actions.yml) to
`.github/workflows/ci.yml` in your application's repository. It builds pull
requests, pushes to `main`, and manual runs. Change `main` if your default branch
has another name, and replace `./gradlew test` with your build command if needed.
Keep `.sdkmanrc` and your build wrapper at the repository root.

Set the repository variable `SDKMAN_CI_IMAGE` to the public image's digest
reference from its release job summary. The image must be published before the
job can start. Updating Java or another SDK then requires changing only
`.sdkmanrc`; keep the image reference fixed until you want to update the base
image itself.

The example caches only `.cache/sdkman/candidates`. Its key includes the runner
OS and architecture, event type, image reference, and `.sdkmanrc` hash. There are
no fallback restore keys. An exact hit skips installation; otherwise
`sdk env install` installs the declared candidates. The build runs in a fresh
Bash step with `sdk env` to activate them, and the cache action saves a new cache
only after a successful job. A missing or empty `.sdkmanrc` fails before cache
lookup. Add `.cache/sdkman/` to the application's `.gitignore`.

The container uses root to write GitHub's mounted workspace and action
directories. The example is intended for the hosted Linux runner; caches and
build files may be root-owned. Keep the `sdkman-app-v1-` cache prefix separate
from privileged release workflows. For a damaged exact-match cache, delete that
cache or bump the prefix to `sdkman-app-v2-` before rerunning.

## Pull request validation

`.github/workflows/pr.yml` runs on pull requests and manual dispatches. It lints
the shell scripts, builds a Linux amd64 image with Docker build checks enabled,
runs the offline smoke test, and tests real SDK installation and offline cache
reuse. Versions live in `tests/.sdkmanrc`, not in the workflow.

The workflow uses read-only repository permissions, disables persisted checkout
credentials, and has no registry login or publishing step. Superseded runs are
cancelled, and job and integration-test timeouts bound stalled downloads. Docker
layers use the `sdkman-ci-pr-amd64` cache scope, separate from release builds.
Candidate downloads start from an empty volume for every job.

No Docker Hub credentials are needed for PR validation. To require it before
merging, configure the repository's branch rules to require `Build and test (amd64)`.
ShellCheck is expected on the GitHub-hosted Ubuntu runner.

## Release publishing

`.github/workflows/release.yml` runs when a release is published, including a
prerelease. It validates the tag before starting the image build. Both jobs check
out the commit identified by the release event, so validation and building use
the same source even if the tag later moves.

Within this repository, release runs for the same tag share a concurrency group.
An active run is allowed to finish (`cancel-in-progress: false`), so a newer run
does not interrupt its push. The group retains at most one pending run, which a
newer pending run can replace. Group names are case-insensitive.

The build job lints the scripts, runs the tag regression checks, and builds a
Linux amd64 image named `sdkman-ci:<release-tag>` with Docker build checks enabled.
It then runs the same offline smoke test, fresh SDK installation, compilation,
and offline candidate-cache reuse checks as PR validation. Release builds use
the separate `sdkman-ci-release-amd64` Docker cache scope.

After all checks succeed, the workflow tags the tested image as
`docker.io/<namespace>/<repository>:<release-tag>`, logs in to Docker Hub, and
pushes that image. Docker validates the target image reference before login.
The job keeps read-only GitHub repository permissions and bounded execution
times. Docker credentials are supplied only to the configuration check and login
step; the login action is configured to log out during cleanup.

Before publishing a release, create a
[public Docker Hub repository](https://docs.docker.com/docker-hub/repos/create/)
and configure these GitHub Actions repository settings:

| Name | Kind | Value |
| --- | --- | --- |
| `DOCKERHUB_USERNAME` | Variable | Docker Hub account with write access to the target repository |
| `DOCKERHUB_REPOSITORY` | Variable | Full `namespace/repository`, such as `your-org/sdkman-ci`, without a registry hostname or tag |
| `DOCKERHUB_TOKEN` | Secret | A personal access token for that account with Read and Write permissions |

The namespace can belong to an organization; the username must identify the
account that owns the token. Create a
[Docker Hub access token](https://docs.docker.com/security/access-tokens/personal-access-tokens/)
with the permissions needed to push, and store it as the repository secret.
Missing settings fail the release job before the image build starts. PR builds
continue to run without these settings or credentials.

Publish a release from a commit containing this workflow to trigger it. The
resulting image supports Linux amd64 and uses the complete release tag. For
example, release `v1.2.3` publishes `docker.io/your-org/sdkman-ci:v1.2.3` when
`DOCKERHUB_REPOSITORY` is `your-org/sdkman-ci`. Use that image reference in consuming
CI jobs, with the application's SDK versions still selected by its `.sdkmanrc`.

The release workflow supplies these image labels through the existing
[Docker build action](https://docs.docker.com/build/ci/github-actions/manage-tags-labels/):

| Label | Value |
| --- | --- |
| `org.opencontainers.image.version` | Complete release tag, including any leading `v` |
| `org.opencontainers.image.revision` | Full source commit SHA used by checkout |
| `org.opencontainers.image.source` | URL of the repository that built the image |

After pulling a release image, inspect its labels locally (substitute your image
reference for the example):

```sh
docker image inspect --format '{{json .Config.Labels}}' \
  docker.io/your-org/sdkman-ci:v1.2.3
```

These release labels are supplied by the workflow. The local build command above
requires no release metadata arguments.

The release job summary also includes a copyable digest reference in the form
`docker.io/<namespace>/<repository>@sha256:<digest>`. Use it to pin a consuming
CI job to that exact image. The digest comes from this job's
[Docker push output](https://docs.docker.com/reference/cli/docker/image/push/),
so moving the release tag later does not change the recorded reference.
Pinning the base image still leaves SDK versions controlled by `.sdkmanrc`.

The publishing script streams push output into the job log and only writes the
summary after a successful push with exactly one valid digest. If reporting fails, the
job fails even though the image may already be in Docker Hub; inspect the push
log before retrying. Run its regression checks without Docker or credentials:

```sh
bash tests/publish-image.sh
```

Both workflows run these checks before building the image.

Release tags must already match the
[Docker tag grammar](https://pkg.go.dev/github.com/distribution/reference#pkg-overview):
1-128 ASCII letters, digits, underscores, dots, or hyphens, starting with a letter,
digit, or underscore. Tags such as `v1.2.3`, `v1.2.3-rc.1`, and `2024.09.23` are
accepted. Tags containing spaces, slashes, or `+` are rejected. The published image
tag will preserve the complete release tag, including any leading `v`.

Validate a proposed tag locally and run the regression checks without Docker:

```sh
bash scripts/validate-release-tag.sh 'v1.2.3'
bash tests/release-tag.sh
```

PR validation also runs these checks. Release tag values are passed to the
validator as quoted arguments through an environment variable, so they are
handled as data rather than shell code.

## Gradual modernization: 2024 to 2026

The current checkpoint is a 2024-era baseline: Debian 12, Checkout v4, Buildx v3,
Build/Push v6, and Java/Kotlin examples from 2024. Non-interactive SDKMAN settings
are configured explicitly. This is a progression of tooling choices, not a
frozen historical build: action major tags can move, and a fresh image build
fetches the stable SDKMAN installer and current Debian packages.

The next checkpoints will strengthen release handling, then progress through
2025/2026 hardening: verified immutable dependency references, automated update
proposals, multi-platform validation, provenance, and an SBOM. Each checkpoint
has its own review and commit. Release publishing requires the repository
variables and secret described above.

Reference: [SDKMAN installation](https://sdkman.io/install/),
[project environments and configuration](https://sdkman.io/usage/),
[Docker build checks](https://docs.docker.com/build/checks/), and
[Docker build caching](https://docs.docker.com/build/ci/github-actions/cache/)
