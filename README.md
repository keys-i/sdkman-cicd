# SDKMAN CI

Use one `.sdkmanrc` across GitHub Actions, Jenkins, GitLab, and any Docker-capable CI.
The image includes SDKMAN and Git, with no preinstalled JDK:

```ini
java=25.0.4.1-tem
kotlin=2.4.20
```

Kotlin is optional. Choose available versions with `sdk list java` and `sdk list kotlin`.
The examples use release tag `v1.2.3`; replace it with a published version.

## GitHub Action

Check out your application, then run its build with the SDKs from `.sdkmanrc`:

```yaml
jobs:
  build:
    runs-on: ubuntu-24.04
    permissions:
      contents: read
    steps:
      - uses: actions/checkout@v6
        with:
          persist-credentials: false
      - uses: keys-i/sdkman-cicd@v1.2.3
        with:
          run: ./gradlew test
```

The Action installs an isolated SDKMAN CLI and caches candidates between successful
jobs. Cache keys include the OS, architecture, event, and `.sdkmanrc` contents.
Selected SDKs apply to commands inside `run`. No image configuration is needed.

| Input | Default | Purpose |
| --- | --- | --- |
| `run` | Required | Bash commands, such as `./mvnw verify` or a multiline build |
| `working-directory` | `.` | Directory inside the checkout containing `.sdkmanrc` |
| `cache` | `true` | Set to `false` to disable the Actions cache |

Use a Linux runner with Bash, curl, zip, unzip, and shasum. See the
[complete workflow](examples/github-actions.yml) for PRs, merge queues, and test reports.

## Jenkins, GitLab, and other CI

Release images are published to `ghcr.io/keys-i/sdkman-cicd:<release-tag>`.
Use the digest from the release workflow summary to pin an image.

| Platform | Example | Setup |
| --- | --- | --- |
| Jenkins | [Jenkinsfile](examples/Jenkinsfile) | Docker Pipeline and JUnit plugins; a Linux amd64 agent labeled `docker-amd64` |
| GitLab | [.gitlab-ci.yml](examples/gitlab-ci.yml) | Linux amd64 Docker runner; set the image reference in the file |
| Other CI / local | Command below | Docker and a writable application checkout |

Both CI examples cache candidates and publish JUnit reports. Jenkins caches live
in each job's workspace; keep untrusted branches in separate multibranch jobs.
Keep GitLab's protected-branch caches separate.

```sh
docker run --rm \
  --mount "type=bind,src=$PWD,dst=/workspace" \
  --env SDKMAN_CANDIDATES_DIR=/workspace/.cache/sdkman/candidates \
  ghcr.io/keys-i/sdkman-cicd:v1.2.3 \
  bash -c '(sdk env || sdk env install) && bash -c "sdk env && ./gradlew test"'
```

Use Bash without `set -u` when calling SDKMAN. The image runs as UID/GID 1000;
mounts must be writable by that user, or use `--user 0` where required.
Set `SDKMAN_CANDIDATES_DIR` to an absolute, writable cache path. Cache candidates
only, keeping `/opt/sdkman` intact. Key image caches by OS, architecture, image,
and `.sdkmanrc`; add `.cache/sdkman/` to your application's `.gitignore`.

## Releases and Marketplace

Every published release or prerelease triggers a fresh build, SDK tests, and a
vulnerability scan, then publishes the tested amd64 image to GHCR under that exact
tag. The publisher verifies the archive checksum and image ID, rescans, pushes,
and checks the published digest. PRs never publish. ARM64 is tested on scheduled
public-repository builds and can be selected manually; release images are amd64.

Publishing uses the repository's `GITHUB_TOKEN` with `packages: write` in the
publish job. No Docker Hub account or registry secret is needed. After the first
publication, [set the GHCR package visibility to public](https://docs.github.com/en/packages/working-with-a-github-packages-registry/working-with-the-container-registry#pushing-container-images)
so Jenkins, GitLab, and Docker can pull anonymously. Existing packages must grant
this repository Actions access.

For [GitHub Marketplace](https://docs.github.com/en/actions/how-tos/create-and-publish-actions/publish-in-github-marketplace),
make the repository public, accept the Marketplace Developer Agreement, and select
**Publish this Action to the GitHub Marketplace** when creating the release.
GitHub checks the Action name's availability. The root [action.yml](action.yml)
supplies the listing metadata; [MIT](LICENSE) covers this project's code.

The workflow stores scan reports, a CycloneDX SBOM with checksum, the tested image
archive, and publication metadata. Reports and archives expire after seven days;
SBOM and publication metadata use repository retention. If an image was pushed
before a later failure, inspect the push log before retrying. There is no automatic
publication of older releases.

## Development

```sh
bash .github/workflowes/scripts/check.sh
docker build --tag sdkman-ci:local .
bash .github/workflowes/scripts/lint-workflows.sh
bash .github/workflowes/scripts/check-image.sh sdkman-ci:local
```

Offline checks need Bash, ShellCheck, jq, and shasum. Image checks install Java
17/21/25/26 and Kotlin, compile programs, and verify offline cache reuse.
PR and release workflows also exercise the local Marketplace Action.
Require `Build and test (amd64)` in branch rules.

Dependabot updates workflow dependencies and the Debian base weekly. Update example
versions and pinned Actionlint/Trivy images manually. Debian packages and SDKMAN
are downloaded at build time, so rebuilding a source revision can change its image.
