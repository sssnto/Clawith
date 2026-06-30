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
