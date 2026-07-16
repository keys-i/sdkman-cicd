# SDKMAN CI image

A Linux amd64 CI image with SDKMAN and Git, without a preinstalled JDK.
Choose Java, Kotlin, and other SDK versions in your application's `.sdkmanrc`.

## Quick start

Build this repository:

```sh
docker build --tag sdkman-ci:local .
```

Create `.sdkmanrc` in your application's root:

```ini
java=21.0.4-tem
kotlin=2.0.20
```

These are 2024 examples; choose exact versions with `sdk list java` and
`sdk list kotlin`. Kotlin is optional.

Run from the application's root, replacing `./gradlew test` as needed:

```sh
docker run --rm \
  --mount "type=bind,src=$PWD,dst=/workspace" \
  --env SDKMAN_CANDIDATES_DIR=/workspace/.cache/sdkman/candidates \
  sdkman-ci:local bash -c 'sdk env install && bash -c "sdk env && ./gradlew test"'
```

Use **Bash** without `set -u` when calling SDKMAN. It loads automatically;
start a fresh shell after installation to load candidate paths. Mounts must be
writable by UID/GID 1000, or use `--user 0` when your runner requires root.

## Caching

Set `SDKMAN_CANDIDATES_DIR` to an absolute, writable path. Restore it before
installation and save it after SDK validation. Cache candidates only; keep
`/opt/sdkman` intact and add `.cache/sdkman/` to `.gitignore`.

Key caches by OS, architecture, image reference, and `.sdkmanrc` hash. Separate
untrusted PR and release caches; clear damaged caches before retrying.
With candidates cached, activate them using `sdk env`; `sdk env install` can
still contact the SDKMAN API.

## CI examples

Pin a public image's digest from its release summary. Keep `.sdkmanrc` and your
build wrapper at the application root.

| Platform | Copy to | Setup |
| --- | --- | --- |
| [GitHub Actions](examples/github-actions.yml) | `.github/workflows/ci.yml` | Set repository variable `SDKMAN_CI_IMAGE`; adjust the `main` branch filter if needed |
| [GitLab CI](examples/gitlab-ci.yml) | `.gitlab-ci.yml` | Set `image.name` directly in the file so image changes invalidate its cache |

Both examples use amd64 containers as root and install SDKs only if `sdk env`
fails. The GitHub example also checks merge queues. Adapt GitLab's hosted Docker
runner tag for your runner and keep protected-branch caches separate.

## Local checks

Offline checks require Bash, ShellCheck, and jq:

```sh
bash .github/workflowes/scripts/check.sh
```

With Docker, lint workflows and test the locally built image. SDK installation
needs internet; the image test never pulls the image:

```sh
bash .github/workflowes/scripts/lint-workflows.sh
bash .github/workflowes/scripts/check-image.sh sdkman-ci:local
```

Image checks cover root/default users, Java 17/21/25/26, Kotlin 2.0.20/2.4.10,
compilation, and offline cache reuse at a different path.
[PRs, merge queues](.github/workflows/pr.yml), and releases run the same checks
plus vulnerability scanning. Require `Build and test (amd64)` in branch rules.
Weekly uncached builds also test ARM64 in public repositories. Manual validation
offers `no_cache` and `architecture` (`amd64`, `arm64`, or `both`); ARM64 requires
`ubuntu-24.04-arm`. Releases remain amd64.

## Publishing releases

Create a public Docker Hub repository and a GitHub [environment](https://docs.github.com/en/actions/how-tos/deploy/configure-and-manage-deployments/manage-environments)
named `dockerhub`. Under **Deployment branches and tags**, select **Selected
branches and tags** and add a **Tag** rule such as `v*`. Configure:

| Name | Type | Value |
| --- | --- | --- |
| `DOCKERHUB_USERNAME` | Repository variable | Account with write access to the repository |
| `DOCKERHUB_REPOSITORY` | Repository variable | Lowercase `namespace/repository`, without a hostname, tag, or digest |
| `DOCKERHUB_TOKEN` | `dockerhub` environment secret | That account's personal access token with Read and Write permissions |

Move any existing `DOCKERHUB_TOKEN` repository secret into this environment.
Private GitHub repositories require Pro, Team, or Enterprise for environments.

Publishing a release or prerelease triggers the [release workflow](.github/workflows/release.yml):
an uncached build, tests, and a Trivy scan, followed by the environment's publish
job. It checks the archive checksum and image ID, rescans before login, and pushes
`docker.io/<namespace>/<repository>:<release-tag>`. Fixable HIGH/CRITICAL findings
or scanner errors block publishing. A digest pull verifies the published image ID.

Tags are preserved (`v1.2.3` is valid; spaces, slashes, and `+` are rejected).
The job summary supplies the digest for CI pinning. Scan reports (also on scan
failure) and the tested archive expire after seven days. The CycloneDX SBOM with
SHA-256 sidecar and `published-image.json` (tag, digest, image ID) follow the
repository's artifact retention policy.
Verify extracted SBOM files with `sha256sum --check sbom.cdx.json.sha256`.

If artifacts expire during an environment wait, rerun all jobs. Publish-only
reruns retain the original destination. If verification or digest reporting
fails after pushing, check the push log before retrying: the image may be published.

## Maintenance

[Dependabot](.github/dependabot.yml) checks workflow Actions and the Docker base
weekly. Update examples and pinned Actionlint/Trivy images manually.
The Debian 13 base is pinned by digest; Debian packages and SDKMAN are fetched
at build time and can change between builds.
