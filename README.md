# SDKMAN CI image

A Linux amd64 CI image with SDKMAN, Git, and no preinstalled JDK. Keep Java, Kotlin,
and other SDK versions in your application's `.sdkmanrc`.

## Quick start

Build from this repository:

```sh
docker build --tag sdkman-ci:local .
```

In your application's root, create `.sdkmanrc` with exact candidate versions:

```ini
java=21.0.4-tem
kotlin=2.0.20
```

These are 2024 examples. Use `sdk list java` or `sdk list kotlin` to choose
versions; Kotlin is optional.

Run from the application's root, replacing `./gradlew test` as needed:

```sh
docker run --rm \
  --mount "type=bind,src=$PWD,dst=/workspace" \
  --env SDKMAN_CANDIDATES_DIR=/workspace/.cache/sdkman/candidates \
  sdkman-ci:local bash -c 'sdk env install && bash -c "sdk env && ./gradlew test"'
```

Use **Bash** and leave `set -u` disabled while calling SDKMAN. SDKMAN loads in
interactive shells and through `BASH_ENV` for scripts. A fresh shell after
installation loads candidate paths. Mounted directories must be writable by
UID/GID 1000, or use `--user 0` when your runner requires root.

## Caching

Set `SDKMAN_CANDIDATES_DIR` to an absolute, writable path. Restore that directory
before installation and save it after SDK validation. Cache only candidates, keeping
the image's `/opt/sdkman` installation intact.

Include OS, architecture, image reference, and the `.sdkmanrc` hash in cache keys.
Separate untrusted PR caches from release caches, and add `.cache/sdkman/` to
`.gitignore`. Clear a damaged cache or change its key prefix before retrying.

For an offline build with all candidates cached, use `sdk env && ./gradlew test`.
`sdk env install` can still contact the SDKMAN API.

## CI examples

Use a published public image's digest reference from its release summary.
Keep `.sdkmanrc` and your build wrapper at the application root.

| Platform | Copy to | Setup |
| --- | --- | --- |
| [GitHub Actions](examples/github-actions.yml) | `.github/workflows/ci.yml` | Set repository variable `SDKMAN_CI_IMAGE`; adjust the `main` branch filter if needed |
| [GitLab CI](examples/gitlab-ci.yml) | `.gitlab-ci.yml` | Set `image.name` directly in the file so image changes invalidate its cache |

Both examples use Linux amd64 containers as root for workspace permissions.
The GitLab example selects a hosted Docker runner; adapt its tag for your own
runner and keep protected-branch caches separate. Both examples try `sdk env`
first and install only when activation fails. GitHub reuses SDKs across `.sdkmanrc`
changes and saves validated SDKs before the build when there was no exact cache hit.

## Local checks

From this repository, run the offline checks with Bash, ShellCheck, and jq:

```sh
bash .github/workflowes/scripts/check.sh
```

Lint workflows as CI does with `bash .github/workflowes/scripts/lint-workflows.sh`
(requires Docker and uses a pinned Actionlint image).

Build the image locally first; tests never pull it. SDK installation needs internet:

```sh
bash .github/workflowes/scripts/check-image.sh sdkman-ci:local
```

The command smoke-tests the default and root users, runs [integration tests](tests/integration.sh),
then removes its temporary cache volume. It installs Java 17, 21, and 25 with Kotlin
2.0.20 and 2.3.10, compiles programs, and tests cache reuse offline at a different path.
[PR validation](.github/workflows/pr.yml)
and releases use the same command. PRs and merge queues need no registry credentials.
All validation builds also scan the tested image using the release vulnerability policy.
Scan output is saved in seven-day `scan-report-*` artifacts, including failed scans.
For branch protection or merge queues, require `Build and test (amd64)` in branch rules.
A weekly uncached build checks upstream changes on amd64, plus ARM64 in public repositories.
Manual runs of
**Validate CI image** offer `no_cache` and an `architecture` choice: `amd64`, `arm64`,
or `both` for parallel tests. ARM64 testing requires access to `ubuntu-24.04-arm`;
release images remain amd64.

## Publishing releases

Create a public Docker Hub repository and a GitHub [environment](https://docs.github.com/en/actions/how-tos/deploy/configure-and-manage-deployments/manage-environments)
named `dockerhub`. Under **Deployment branches and tags**, choose **Selected branches
and tags** and add a **Tag** rule matching your releases, such as `v*`. Configure:

| Name | Type | Value |
| --- | --- | --- |
| `DOCKERHUB_USERNAME` | Repository variable | Account with write access to the repository |
| `DOCKERHUB_REPOSITORY` | Repository variable | Lowercase `namespace/repository`, without a hostname, tag, or digest |
| `DOCKERHUB_TOKEN` | `dockerhub` environment secret | That account's personal access token with Read and Write permissions |

Move any existing `DOCKERHUB_TOKEN` repository secret into this environment.
Private GitHub repositories require Pro, Team, or Enterprise for environments.

Publishing a release, including a prerelease, triggers the
[release workflow](.github/workflows/release.yml). It validates the tag and destination format, builds,
tests, and scans the image before the `dockerhub` publish job starts. Trivy blocks
publishing on fixable HIGH/CRITICAL vulnerabilities or scanner errors. That job checks the
archive checksum before loading it, verifies its image ID, then pushes
`docker.io/<namespace>/<repository>:<release-tag>`. It pulls the published digest
and checks that its image ID matches the tested image. Artifacts expire after seven days;
rerun all jobs if one expires while waiting for an environment rule.
Publishing uses the destination recorded by the build job, including on publish-only reruns.
The publish job scans again after environment approval and before Docker Hub login,
including on reruns; new fixable HIGH/CRITICAL findings block the push.
Release builds bypass layer caches to refresh Debian packages and SDKMAN.
They retain a [CycloneDX SBOM](https://trivy.dev/docs/v0.68/guide/supply-chain/sbom/)
of the tested image in a seven-day `release-sbom-*` artifact, after checking its
image ID and nonempty component list.
The artifact includes a SHA-256 file, also recorded in the build summary. After
extracting both files, verify with `sha256sum --check sbom.cdx.json.sha256`.
The full tag is preserved. Tags such as `v1.2.3` are valid; spaces, slashes, and
`+` are rejected by the [tag validator](.github/workflowes/scripts/validate-release-tag.sh).

The job summary provides the digest reference for pinning CI images. Release
images also carry version, source commit, and repository labels. If verification or
digest reporting fails, the image may already be published; check the push log before
retrying.

## Modernization

[Dependabot](.github/dependabot.yml) checks workflow Actions and the Docker base weekly,
grouping artifact upload/download version updates. Update `examples/` and the
pinned Actionlint and [Trivy](https://trivy.dev/docs/v0.68/guide/references/configuration/cli/trivy_image/)
images manually; they are outside its configured coverage.
The Debian 13 base is pinned by digest. Builds still fetch current Debian packages
and SDKMAN, so these tooling stages are not historical reproductions. Later
checkpoints target Action and SDKMAN pinning, multi-platform validation,
and provenance through 2025–2026.
