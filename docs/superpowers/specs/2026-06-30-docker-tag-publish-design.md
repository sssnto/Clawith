# Docker Tag Publish and Fork-Safe Sync Design

## Context

This repository is a fork of `dataelement/Clawith`. It is periodically synchronized from the upstream repository with GitHub's **Sync fork** feature.

The fork previously contained `.github/workflows/docker-publish.yml`. That workflow built and pushed backend and frontend Docker images when a `v*` tag was pushed. The current branch no longer contains that file, so pushing `v1.10.4` did not start a Docker build. Historical GitHub Actions runs confirm that the old workflow successfully published multi-platform Docker Hub images through `v1.8.3-beta2`.

The design must restore tag-based Docker publishing while keeping the fork easy to synchronize without losing fork-specific files.

## Goals

- Trigger Docker publishing automatically when a tag matching `v*` is pushed.
- Publish backend and frontend images to Docker Hub.
- Build both `linux/amd64` and `linux/arm64` images.
- Publish an immutable version tag derived from the Git tag.
- Publish `latest` only for stable semantic versions, not prerelease tags.
- Provide a manual recovery path for an existing tag such as `v1.10.4`.
- Preserve the workflow during normal GitHub **Sync fork → Update branch** operations.
- Document the sync constraint so maintainers do not accidentally discard fork-specific commits.

## Non-Goals

- Changing the existing release pull-request workflow.
- Replacing Drone CI.
- Publishing images to GHCR.
- Automatically deploying images to a server or Kubernetes cluster.
- Making fork-specific files survive an intentional **Discard commits** or force-push operation. Those operations replace branch history by design.

## Chosen Approach

Use a single fork branch with a dedicated GitHub Actions workflow committed to `main`.

The workflow remains isolated from `.github/workflows/release.yml`. GitHub's normal **Sync fork → Update branch** operation merges or fast-forwards upstream changes while retaining fork-specific commits. Maintainers must not select **Discard commits**, because no repository file can protect itself from an intentional branch reset.

This approach has less operational overhead than maintaining separate upstream-mirror and customization branches, while preserving the existing tag-and-release workflow used by this fork.

## Workflow Design

Create `.github/workflows/docker-publish.yml` with two triggers:

1. `push.tags: ["v*"]` for normal tag-driven publishing.
2. `workflow_dispatch` with a required tag input for rebuilding an existing tag.

For a tag push, the source ref is the pushed tag. For a manual run, the workflow checks out the requested tag. The tag must match a version-shaped `v*` value and must resolve in the repository before any registry login or image build starts.

The workflow will:

1. Check out the selected tag.
2. Set up QEMU and Docker Buildx.
3. Log in to Docker Hub with `DOCKERHUB_USERNAME` and `DOCKERHUB_TOKEN`.
4. Build and push `backend/Dockerfile`.
5. Build and push `frontend/Dockerfile`.
6. Publish both architectures in a manifest list.

The backend image names are:

- `${DOCKERHUB_USERNAME}/clawith-backend:<version>`
- `${DOCKERHUB_USERNAME}/clawith-backend:latest` for stable tags only

The frontend image names follow the same pattern:

- `${DOCKERHUB_USERNAME}/clawith-frontend:<version>`
- `${DOCKERHUB_USERNAME}/clawith-frontend:latest` for stable tags only

The `<version>` value removes the leading `v`; for example, `v1.10.4` publishes `1.10.4`.

## Prerelease Handling

Tags containing a prerelease suffix, such as `v1.11.0-beta.1` or `v1.11.0-rc1`, publish only their versioned image tags. They do not update `latest`.

This prevents test or prerelease images from silently replacing the stable Docker Hub image.

## Failure Handling

- A missing or malformed manual tag fails before image construction.
- Missing Docker Hub secrets fail at the login step without exposing secret values.
- Backend and frontend builds are separate named steps so failures identify the affected image.
- Docker Buildx reports architecture-specific build failures.
- A failed build does not produce a successful multi-platform manifest for that image.

## Fork Synchronization Safety

Add a short maintenance document that states:

1. Use GitHub **Sync fork → Update branch**.
2. Never use **Discard commits** when fork-specific commits exist.
3. Keep force pushes disabled for `main`.
4. After each sync, confirm `.github/workflows/docker-publish.yml` still exists.
5. Create release tags from a commit that contains the Docker workflow.

Repository settings should protect `main` from force pushes. This setting is external to the Git repository and must be configured in GitHub.

## Validation

Before committing the implementation:

- Parse the workflow as YAML.
- Assert that the workflow listens for `v*` tag pushes.
- Assert that manual dispatch accepts a tag.
- Assert that checkout uses the selected tag.
- Assert that both Dockerfile paths exist.
- Assert that both images publish version tags.
- Assert that prereleases do not update `latest`.
- Run any available GitHub Actions workflow linter.

After pushing the implementation:

- Manually dispatch the workflow for `v1.10.4`, because adding a workflow does not retroactively process the earlier tag-push event.
- Confirm the Actions run checks out commit `fa8a429`.
- Confirm Docker Hub contains backend and frontend manifests tagged `1.10.4`.

## Operational Constraint

The existing release workflow creates tags with the repository `GITHUB_TOKEN`. GitHub suppresses most secondary workflow triggers caused by that token. This design guarantees automatic Docker publishing for tags pushed by a user or external credential. Connecting the release-PR workflow directly to Docker publishing is intentionally outside this change and can be added later through a reusable workflow call.
