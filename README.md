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
  sdkman-ci:local bash -c 'sdk env install && sdk env && ./gradlew test'
```

Replace `./gradlew test` with your build command. Keep installation, activation,
and the build in the same Bash process so it retains the selected SDK environment.
The `&&` chain prevents a build from starting when installation or activation fails.

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
  sdkman-ci:local bash -c 'sdk env install && sdk env && ./gradlew test'
```

Configure your CI platform to restore `.cache/sdkman/candidates` before that
command and save it after a successful job. Include the OS, architecture, image
release, and a hash of `.sdkmanrc` in the cache key. Keep caches separate across
trust boundaries, such as untrusted pull requests and release jobs. Cache only
the candidates directory, not all of `/opt/sdkman`, which would overwrite the
image's CLI and configuration. Exclude the cache from source control.

SDKMAN's initializer currently assigns its candidate path unconditionally. The
build applies a small checked change to honor `SDKMAN_CANDIDATES_DIR` before
restoring `JAVA_HOME`, other candidate homes, and `PATH`. If that upstream code
changes, the build fails with a request to review the compatibility change.

The image runs as user `sdkman` (UID/GID 1000). Mounted workspaces and caches must
be writable by that user. If a runner requires root, configure it to run the
container with `--user 0`; account for the resulting file ownership on the host.

## Image lifecycle

This first increment provides a local Docker build. Docker Hub publishing is not configured yet.
The Dockerfile currently fetches the stable SDKMAN installer at build time, so
rebuilds can contain newer SDKMAN and Debian packages. Do not treat the local tag
as a reproducible release pin.

Next increments, each with a separate review and commit checkpoint:

1. PR builds and validation, including real SDK installation, build caching,
   minimal workflow permissions, and supply-chain checks
2. Release-only Docker Hub publishing with release tags, multi-platform testing,
   provenance, an SBOM, and documented credentials and release procedures

Reference: [SDKMAN installation and CI mode](https://sdkman.io/install/),
[project environments and configuration](https://sdkman.io/usage/)
