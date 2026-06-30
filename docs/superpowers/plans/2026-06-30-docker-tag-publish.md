# Docker Tag Publish Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Restore fork-safe Docker Hub publishing so user-pushed `v*` tags automatically build backend and frontend images for AMD64 and ARM64.

**Architecture:** Add one dedicated GitHub Actions workflow that supports both tag-push and manual backfill execution. Keep fork synchronization guidance and a standard-library validation script beside the workflow so the fork-specific behavior can be checked after every upstream sync.

**Tech Stack:** GitHub Actions, Docker Buildx, Docker Hub, Python 3 standard library

---

### Task 1: Add a failing workflow contract validator

**Files:**
- Create: `.github/scripts/validate_docker_publish_workflow.py`
- Test: `.github/scripts/validate_docker_publish_workflow.py`

- [ ] **Step 1: Write the failing validation script**

```python
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
WORKFLOW = ROOT / ".github/workflows/docker-publish.yml"
MAINTENANCE = ROOT / ".github/FORK_MAINTENANCE.md"


def require(text: str, fragment: str, label: str) -> None:
    if fragment not in text:
        raise AssertionError(f"missing {label}: {fragment}")


if not WORKFLOW.is_file():
    raise AssertionError(f"missing Docker publish workflow: {WORKFLOW}")

workflow = WORKFLOW.read_text(encoding="utf-8")
for fragment, label in [
    ("push:", "push trigger"),
    ("tags:", "tag filter"),
    ("- 'v*'", "v-prefixed tag pattern"),
    ("workflow_dispatch:", "manual trigger"),
    ("tag:", "manual tag input"),
    ("DOCKERHUB_USERNAME", "Docker Hub username secret"),
    ("DOCKERHUB_TOKEN", "Docker Hub token secret"),
    ("linux/amd64,linux/arm64", "multi-platform build"),
    ("./backend", "backend build context"),
    ("./frontend", "frontend build context"),
    ("clawith-backend:", "backend image"),
    ("clawith-frontend:", "frontend image"),
    ("stable=true", "stable release output"),
    ("stable=false", "prerelease output"),
    (":latest", "stable latest tag"),
]:
    require(workflow, fragment, label)

for dockerfile in (ROOT / "backend/Dockerfile", ROOT / "frontend/Dockerfile"):
    if not dockerfile.is_file():
        raise AssertionError(f"missing Dockerfile: {dockerfile}")

if not MAINTENANCE.is_file():
    raise AssertionError(f"missing fork maintenance guide: {MAINTENANCE}")

maintenance = MAINTENANCE.read_text(encoding="utf-8")
require(maintenance, "Update branch", "safe Sync fork action")
require(maintenance, "Discard commits", "unsafe Sync fork warning")
require(maintenance, "force push", "force-push warning")

print("Docker publish workflow contract is valid.")
```

- [ ] **Step 2: Run the validator to verify it fails**

Run: `python3 .github/scripts/validate_docker_publish_workflow.py`

Expected: FAIL with `AssertionError: missing Docker publish workflow`.

### Task 2: Implement tag-driven Docker Hub publishing

**Files:**
- Create: `.github/workflows/docker-publish.yml`
- Test: `.github/scripts/validate_docker_publish_workflow.py`

- [ ] **Step 1: Add the minimal workflow**

```yaml
name: Build and Push to Docker Hub

on:
  push:
    tags:
      - 'v*'
  workflow_dispatch:
    inputs:
      tag:
        description: Existing v-prefixed tag to build
        required: true
        type: string

permissions:
  contents: read

concurrency:
  group: docker-publish-${{ github.event_name == 'workflow_dispatch' && inputs.tag || github.ref_name }}
  cancel-in-progress: false

jobs:
  publish:
    name: Publish Docker images
    runs-on: ubuntu-latest
    env:
      RELEASE_TAG: ${{ github.event_name == 'workflow_dispatch' && inputs.tag || github.ref_name }}

    steps:
      - name: Checkout release tag
        uses: actions/checkout@v4
        with:
          ref: ${{ env.RELEASE_TAG }}
          fetch-depth: 0

      - name: Validate release tag
        id: release
        shell: bash
        run: |
          set -euo pipefail

          if [[ ! "$RELEASE_TAG" =~ ^v[0-9]+\.[0-9]+\.[0-9]+([-.][0-9A-Za-z][0-9A-Za-z.-]*)?$ ]]; then
            echo "Invalid release tag: $RELEASE_TAG" >&2
            exit 1
          fi

          git rev-parse --verify "refs/tags/${RELEASE_TAG}^{commit}" >/dev/null
          echo "version=${RELEASE_TAG#v}" >> "$GITHUB_OUTPUT"

          if [[ "$RELEASE_TAG" =~ ^v[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
            echo "stable=true" >> "$GITHUB_OUTPUT"
          else
            echo "stable=false" >> "$GITHUB_OUTPUT"
          fi

      - name: Set up QEMU
        uses: docker/setup-qemu-action@v3

      - name: Set up Docker Buildx
        uses: docker/setup-buildx-action@v3

      - name: Log in to Docker Hub
        uses: docker/login-action@v3
        with:
          username: ${{ secrets.DOCKERHUB_USERNAME }}
          password: ${{ secrets.DOCKERHUB_TOKEN }}

      - name: Build and push backend
        uses: docker/build-push-action@v6
        with:
          context: ./backend
          push: true
          platforms: linux/amd64,linux/arm64
          tags: |
            ${{ secrets.DOCKERHUB_USERNAME }}/clawith-backend:${{ steps.release.outputs.version }}
            ${{ steps.release.outputs.stable == 'true' && format('{0}/clawith-backend:latest', secrets.DOCKERHUB_USERNAME) || '' }}

      - name: Build and push frontend
        uses: docker/build-push-action@v6
        with:
          context: ./frontend
          push: true
          platforms: linux/amd64,linux/arm64
          tags: |
            ${{ secrets.DOCKERHUB_USERNAME }}/clawith-frontend:${{ steps.release.outputs.version }}
            ${{ steps.release.outputs.stable == 'true' && format('{0}/clawith-frontend:latest', secrets.DOCKERHUB_USERNAME) || '' }}
```

- [ ] **Step 2: Run the validator and observe the remaining expected failure**

Run: `python3 .github/scripts/validate_docker_publish_workflow.py`

Expected: FAIL with `AssertionError: missing fork maintenance guide`.

### Task 3: Document fork-safe synchronization

**Files:**
- Create: `.github/FORK_MAINTENANCE.md`
- Test: `.github/scripts/validate_docker_publish_workflow.py`

- [ ] **Step 1: Add the maintenance guide**

```markdown
# Fork Maintenance

This fork contains repository-specific GitHub Actions configuration that is not present upstream.

## Safe upstream synchronization

1. Open **Sync fork** on GitHub.
2. Choose **Update branch**.
3. Do not choose **Discard commits**. It replaces fork history and removes fork-specific files.
4. Do not force push `main`.
5. Confirm `.github/workflows/docker-publish.yml` still exists after synchronization.

Create release tags only from commits containing the Docker publishing workflow.
```

- [ ] **Step 2: Run the contract validator**

Run: `python3 .github/scripts/validate_docker_publish_workflow.py`

Expected: PASS with `Docker publish workflow contract is valid.`

- [ ] **Step 3: Check workflow syntax with actionlint when available**

Run: `if command -v actionlint >/dev/null 2>&1; then actionlint .github/workflows/docker-publish.yml; else echo "actionlint unavailable; contract validation used"; fi`

Expected: exit 0, with no actionlint diagnostics or the documented fallback message.

- [ ] **Step 4: Check repository diff**

Run: `git diff --check && git status --short`

Expected: no whitespace errors; only the workflow and maintenance guide are uncommitted.

- [ ] **Step 5: Commit the validated implementation**

```bash
git add .github/FORK_MAINTENANCE.md .github/scripts/validate_docker_publish_workflow.py .github/workflows/docker-publish.yml
git commit -m "ci: restore Docker publishing for release tags"
```

### Task 4: Verify and publish the repository changes

**Files:**
- Verify: `.github/workflows/docker-publish.yml`
- Verify: `.github/scripts/validate_docker_publish_workflow.py`
- Verify: `.github/FORK_MAINTENANCE.md`

- [ ] **Step 1: Run fresh local verification**

Run:

```bash
python3 .github/scripts/validate_docker_publish_workflow.py
git diff --check origin/main...HEAD
git status --short --branch
```

Expected: validator passes, no whitespace errors, and `main` is ahead of `origin/main` with a clean worktree.

- [ ] **Step 2: Push `main`**

Run: `git push origin main`

Expected: the design, plan, validator, workflow, and maintenance commits are pushed.

- [ ] **Step 3: Verify GitHub contains the workflow**

Run: `git ls-remote origin refs/heads/main`

Expected: remote `main` points to local `HEAD`.

- [ ] **Step 4: Backfill `v1.10.4` manually**

Use GitHub Actions → **Build and Push to Docker Hub** → **Run workflow**, select `main`, and enter `v1.10.4`.

Expected: the workflow checks out `v1.10.4`, publishes backend and frontend tags `1.10.4`, and updates `latest`.

The existing tag must not be deleted or recreated. Future user-pushed `v*` tags will trigger the workflow automatically when the tagged commit includes `.github/workflows/docker-publish.yml`.
